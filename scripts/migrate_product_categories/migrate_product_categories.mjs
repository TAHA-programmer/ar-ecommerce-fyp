// TWin AR — Phase 8.8b product category reference backfill (CLI).
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function,
// NOT reachable from the mobile app — mirrors scripts/migrate_product_images/
// and scripts/seed_products/'s Admin SDK pattern (bypasses firestore.rules
// entirely, same reason those scripts do).
//
// Backfills `categoryId`/`categoryKind` onto live `products/{id}` documents
// that still only carry the legacy `category` field, by matching it against
// a real `categories/{categoryId}` document. See lib.mjs's file comment for
// the full validation/backup/rollback contract.
//
// Usage:
//   node migrate_product_categories.mjs
//     Dry run (default, no flag needed). Performs NO Firebase writes.
//     Reports every product's status: already migrated, needs migration,
//     or blocked (with the exact reason) - invalid legacy value, missing/
//     mismatched category document, or a partially-migrated document.
//
//   node migrate_product_categories.mjs --apply --project=twin-ar-d4d75
//     Live run. Refuses to start unless --project is EXACTLY
//     "twin-ar-d4d75". ALL-OR-NOTHING: if the validation pass finds ANY
//     blocker anywhere in the collection, the run aborts completely with
//     zero writes - fix the flagged documents and re-run. Only once
//     validation is fully clean does it write a timestamped local backup
//     of every affected product's exact prior categoryId/categoryKind
//     state (including whether each field existed at all) to backups/,
//     then apply the narrow `.update({ categoryId, categoryKind })` to
//     each - never a `.set()`, never touching mainImage/galleryMedia/any
//     other field.
//
//   node migrate_product_categories.mjs --rollback=backups/<file>.json
//     Rollback preview (dry run) - prints what would be restored.
//
//   node migrate_product_categories.mjs --rollback=backups/<file>.json --apply --project=twin-ar-d4d75
//     Live rollback - restores categoryId/categoryKind on every product
//     listed in the given backup file to their EXACT original state
//     (deleting a field if it did not exist before this script touched it,
//     never leaving a stray value).
//
// Requires GOOGLE_APPLICATION_CREDENTIALS / `gcloud auth application-default
// login`, exactly as scripts/seed_products/README.md describes.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';

import {
  CONFIRMED_PROJECT_ID,
  DELETE_FIELD,
  applyProductMigration,
  applyRollback,
  assertProjectGuard,
  buildBackupPayload,
  buildFullPlan,
  summarizePlans,
} from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BACKUP_DIR = path.join(__dirname, 'backups');

function parseArgs(argv) {
  const apply = argv.includes('--apply');
  const projectArg = argv.find((a) => a.startsWith('--project='));
  const project = projectArg ? projectArg.slice('--project='.length) : null;
  const rollbackArg = argv.find((a) => a.startsWith('--rollback='));
  const rollbackFile = rollbackArg
    ? rollbackArg.slice('--rollback='.length)
    : null;

  let mode;
  if (rollbackFile) {
    mode = apply ? 'rollback-apply' : 'rollback-dry-run';
  } else {
    mode = apply ? 'apply' : 'dry-run';
  }
  return { mode, project, rollbackFile };
}

function makeFirestoreAdapter(db) {
  return {
    async listProducts() {
      const snap = await db.collection('products').get();
      return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
    },
    async listCategories() {
      const snap = await db.collection('categories').get();
      return snap.docs.map((d) => ({ id: d.id, data: d.data() }));
    },
    async updateProduct(id, fields) {
      // Translate the pure-logic DELETE_FIELD sentinel to the real
      // Admin-SDK FieldValue only here at the boundary - lib.mjs stays
      // firebase-admin-free and unit-testable with a plain fake.
      const resolved = {};
      for (const [key, value] of Object.entries(fields)) {
        resolved[key] = value === DELETE_FIELD
          ? admin.firestore.FieldValue.delete()
          : value;
      }
      await db.collection('products').doc(id).update(resolved);
    },
  };
}

function printReport(summary) {
  console.log('--- Phase 8.8b — Product Category Backfill: VALIDATION REPORT ---');
  console.log(`Products scanned: ${summary.productsScanned}`);
  console.log(`Already migrated (no change needed): ${summary.alreadyMigratedCount}`);
  console.log(`Documents that would change: ${summary.documentsThatWouldChange.length}`);
  for (const id of summary.documentsThatWouldChange) console.log(`  - ${id}`);
  console.log(`Blockers found: ${summary.blockers.length}`);
  for (const b of summary.blockers) {
    console.log(`  - [${b.status}] ${b.productId}: ${b.reason}`);
  }
  console.log('');
}

async function runDryRun(firestoreAdapter) {
  const plans = await buildFullPlan(firestoreAdapter);
  const summary = summarizePlans(plans);
  printReport(summary);
  if (summary.hasBlockers) {
    console.log(
      'BLOCKED: fix the documents listed above before this migration can ' +
        'be applied. No Firebase writes were made.',
    );
  } else if (summary.documentsThatWouldChange.length === 0) {
    console.log('Nothing to migrate - every product is already up to date. No Firebase writes were made.');
  } else {
    console.log(
      'Validation is clean. Re-run with --apply --project=' +
        `${CONFIRMED_PROJECT_ID} to perform the live migration.`,
    );
  }
  return { plans, summary };
}

function writeBackup(plans) {
  mkdirSync(BACKUP_DIR, { recursive: true });
  const payload = buildBackupPayload(plans);
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(BACKUP_DIR, `backup-${timestamp}.json`);
  writeFileSync(filePath, JSON.stringify(payload, null, 2));
  return { filePath, payload };
}

async function runApply(firestoreAdapter) {
  const plans = await buildFullPlan(firestoreAdapter);
  const summary = summarizePlans(plans);
  printReport(summary);

  // All-or-nothing: a single blocker anywhere aborts the entire run before
  // any write happens, so a live dataset can never end up partially
  // migrated by one execution of this script.
  if (summary.hasBlockers) {
    console.log(
      `ABORTED: ${summary.blockers.length} blocker(s) found - see above. ` +
        'Zero writes were performed. Fix the flagged documents and re-run.',
    );
    process.exitCode = 1;
    return;
  }

  if (summary.documentsThatWouldChange.length === 0) {
    console.log('Nothing to migrate - every product is already up to date. No Firebase writes were performed.');
    return;
  }

  // Backup is written before the first Firebase write of this run.
  const { filePath } = writeBackup(plans);
  console.log(`Backup written: ${filePath}`);
  console.log(`Rollback: node migrate_product_categories.mjs --rollback=${filePath} --apply --project=${CONFIRMED_PROJECT_ID}`);
  console.log('\n--- Applying migration ---');

  const changing = plans.filter((p) => p.wouldChange);
  let succeeded = 0;
  let failed = 0;
  for (const plan of changing) {
    const result = await applyProductMigration(plan, firestoreAdapter);
    if (result.ok) {
      succeeded++;
      console.log(`  OK   ${plan.productId} -> categoryId="${plan.targetCategoryId}"`);
    } else {
      failed++;
      console.log(`  FAIL ${plan.productId}: ${result.error}`);
    }
  }
  console.log(`\nDone. ${succeeded} product(s) migrated, ${failed} failed.`);
  if (failed > 0) {
    console.log(
      'Some products failed mid-run after validation passed (e.g. a ' +
        'transient network error) - re-run the dry-run to see current ' +
        'state, or use the backup above to roll back what succeeded.',
    );
  }
}

async function runRollback(firestoreAdapter, rollbackFile, apply) {
  const payload = JSON.parse(readFileSync(rollbackFile, 'utf8'));
  console.log(`--- Rollback ${apply ? '(LIVE)' : '(DRY RUN)'}: ${rollbackFile} ---`);
  console.log(`Products to restore: ${payload.length}`);
  for (const entry of payload) {
    const idDesc = entry.hadCategoryId
      ? `categoryId="${entry.categoryId}"`
      : 'categoryId deleted (did not exist before)';
    const kindDesc = entry.hadCategoryKind
      ? `categoryKind="${entry.categoryKind}"`
      : 'categoryKind deleted (did not exist before)';
    console.log(`  - ${entry.productId}: ${idDesc}, ${kindDesc}`);
  }

  if (!apply) {
    console.log('\nDry run only - no writes performed. Add --apply --project=' +
      `${CONFIRMED_PROJECT_ID} to actually restore these fields.`);
    return;
  }

  const results = await applyRollback(payload, firestoreAdapter);
  const succeeded = results.filter((r) => r.ok).length;
  const failed = results.length - succeeded;
  for (const r of results) {
    console.log(r.ok ? `  OK   ${r.productId}` : `  FAIL ${r.productId}: ${r.error}`);
  }
  console.log(`\nDone. ${succeeded} restored, ${failed} failed.`);
}

async function main() {
  const { mode, project, rollbackFile } = parseArgs(process.argv.slice(2));

  try {
    assertProjectGuard(mode, project);
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }

  if (mode === 'rollback-dry-run') {
    admin.initializeApp({
      credential: admin.credential.applicationDefault(),
      projectId: CONFIRMED_PROJECT_ID,
    });
    const firestoreAdapter = makeFirestoreAdapter(admin.firestore());
    await runRollback(firestoreAdapter, rollbackFile, false);
    return;
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: CONFIRMED_PROJECT_ID,
  });
  const firestoreAdapter = makeFirestoreAdapter(admin.firestore());

  if (mode === 'rollback-apply') {
    await runRollback(firestoreAdapter, rollbackFile, true);
    return;
  }

  if (mode === 'dry-run') {
    await runDryRun(firestoreAdapter);
    return;
  }

  // mode === 'apply'
  await runApply(firestoreAdapter);
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
