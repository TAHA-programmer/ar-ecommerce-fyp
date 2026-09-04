// TWin AR — Phase 8.7.1 seed/catalogue product image migration (CLI).
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function,
// NOT reachable from the mobile app — mirrors scripts/seed_products/ and
// scripts/super_admin_bootstrap/'s Admin SDK pattern (bypasses
// firestore.rules/storage.rules entirely, same reason those scripts do).
//
// Migrates ONLY `ProductImageRef(source: 'asset')` entries found on live
// Firestore `products/{id}`.mainImage`/`.galleryMedia` to real Firebase
// Storage objects under `products/{productId}/images/{stableFileName}`,
// rewriting those two fields to `source: 'network'` with the resulting
// public download URL. Every other product field, every `network` entry,
// every AR/VTO/logo/avatar asset is left untouched — see README.md.
//
// Usage:
//   node migrate_product_images.mjs
//     Dry run (default, no flag needed). Performs NO Firebase writes.
//     Reports products scanned, asset references found, already-network
//     references skipped, missing/invalid files, planned Storage paths,
//     and which product documents would change.
//
//   node migrate_product_images.mjs --apply --project=twin-ar-d4d75
//     Live run. Refuses to start unless --project is EXACTLY
//     "twin-ar-d4d75". Writes a timestamped local backup of every affected
//     product's original mainImage/galleryMedia to backups/ before making
//     any change, then uploads + updates product-by-product.
//
//   node migrate_product_images.mjs --rollback=backups/<file>.json
//     Rollback preview (dry run) — prints what would be restored.
//
//   node migrate_product_images.mjs --rollback=backups/<file>.json --apply --project=twin-ar-d4d75
//     Live rollback — restores mainImage/galleryMedia on every product
//     listed in the given backup file to their original (pre-migration)
//     values.
//
// Requires GOOGLE_APPLICATION_CREDENTIALS / `gcloud auth application-default
// login`, exactly as scripts/seed_products/README.md describes — the same
// credential works for every script in scripts/.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';

import {
  CONFIRMED_PROJECT_ID,
  applyProductMigration,
  applyRollback,
  buildBackupPayload,
  buildFullPlan,
  buildPublicUrl,
  summarizePlans,
  assertProjectGuard,
} from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..', '..');
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
    async updateProduct(id, fields) {
      await db.collection('products').doc(id).update(fields);
    },
  };
}

function makeStorageAdapter(bucket) {
  return {
    async exists(objectPath) {
      const [exists] = await bucket.file(objectPath).exists();
      return exists;
    },
    async upload(objectPath, buffer, contentType) {
      await bucket
        .file(objectPath)
        .save(buffer, { resumable: false, metadata: { contentType } });
    },
    async delete(objectPath) {
      await bucket.file(objectPath).delete();
    },
    publicUrl(objectPath) {
      return buildPublicUrl(bucket.name, objectPath);
    },
  };
}

function printDryRunReport(summary) {
  console.log('--- Phase 8.7.1 — Product Image Migration: DRY RUN ---');
  console.log(`Products scanned: ${summary.productsScanned}`);
  console.log(`Asset references found (valid + invalid): ${summary.assetReferencesFound}`);
  console.log(`Already-network references skipped: ${summary.alreadyNetworkSkipped}`);
  console.log(`Documents that would change: ${summary.documentsThatWouldChange.length}`);
  for (const id of summary.documentsThatWouldChange) console.log(`  - ${id}`);
  console.log(`Documents blocked (invalid file found, no change will be made): ${summary.documentsBlocked.length}`);
  for (const id of summary.documentsBlocked) console.log(`  - ${id}`);
  console.log(`Documents already fully migrated / no asset refs: ${summary.documentsUntouched}`);
  console.log(`Missing/invalid files: ${summary.missingOrInvalid.length}`);
  for (const m of summary.missingOrInvalid) {
    console.log(`  - [${m.productId}] ${m.path}: ${m.reason}`);
  }
  console.log(`Planned Storage paths (${summary.plannedPaths.length}):`);
  for (const p of summary.plannedPaths) console.log(`  - ${p}`);
  console.log('');
  console.log('No Firebase writes were made. Re-run with --apply --project=' +
    `${CONFIRMED_PROJECT_ID} to perform the live migration.`);
}

function writeBackup(plans) {
  mkdirSync(BACKUP_DIR, { recursive: true });
  const payload = buildBackupPayload(plans);
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(BACKUP_DIR, `backup-${timestamp}.json`);
  writeFileSync(filePath, JSON.stringify(payload, null, 2));
  return { filePath, payload };
}

async function runDryRun(firestoreAdapter) {
  const plans = await buildFullPlan(firestoreAdapter, REPO_ROOT);
  const summary = summarizePlans(plans);
  printDryRunReport(summary);
  return { plans, summary };
}

async function runApply(firestoreAdapter, storageAdapter) {
  const plans = await buildFullPlan(firestoreAdapter, REPO_ROOT);
  const summary = summarizePlans(plans);
  printDryRunReport(summary);

  const changing = plans.filter((p) => p.wouldChange);
  if (changing.length === 0) {
    console.log('\nNothing to migrate — no live writes performed.');
    return;
  }

  const { filePath } = writeBackup(plans);
  console.log(`\nBackup written: ${filePath}`);
  console.log(`Rollback: node migrate_product_images.mjs --rollback=${filePath} --apply --project=${CONFIRMED_PROJECT_ID}`);
  console.log('\n--- Applying migration ---');

  let succeeded = 0;
  let failed = 0;
  for (const plan of changing) {
    const result = await applyProductMigration(plan, {
      firestoreAdapter,
      storageAdapter,
    });
    if (result.ok) {
      succeeded++;
      console.log(`  OK   ${plan.productId} (${result.uploadedCount} object(s) uploaded)`);
    } else {
      failed++;
      console.log(`  FAIL ${plan.productId}: ${result.error}`);
      if (result.rolledBackObjectPaths.length > 0) {
        console.log(`       rolled back: ${result.rolledBackObjectPaths.join(', ')}`);
      }
    }
  }
  console.log(`\nDone. ${succeeded} product(s) migrated, ${failed} failed (left untouched).`);
}

async function runRollback(firestoreAdapter, rollbackFile, apply) {
  const payload = JSON.parse(readFileSync(rollbackFile, 'utf8'));
  console.log(`--- Rollback ${apply ? '(LIVE)' : '(DRY RUN)'}: ${rollbackFile} ---`);
  console.log(`Products to restore: ${payload.length}`);
  for (const entry of payload) console.log(`  - ${entry.productId}`);

  if (!apply) {
    console.log('\nDry run only — no writes performed. Add --apply --project=' +
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
    // No Firestore writes in this mode; still need a client for symmetry
    // with rollback-apply, but it will never call updateProduct.
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
    storageBucket: `${CONFIRMED_PROJECT_ID}.firebasestorage.app`,
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
  const storageAdapter = makeStorageAdapter(admin.storage().bucket());
  await runApply(firestoreAdapter, storageAdapter);
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
