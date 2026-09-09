// TWin AR — Phase 9.2 coverage-expansion Room-AR rollout (CLI).
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function, NOT
// reachable from the mobile app — mirrors scripts/upload_ar_models/'s and
// scripts/migrate_ar_catalogue/'s Admin SDK pattern (bypasses storage.rules /
// firestore.rules entirely, same reason those scripts do).
//
// Uploads the six developer + supervisor-approved GLB designs
// (`_ar_assets/candidates/*_chatgpt_original.glb`) to their 26 destination
// products' versioned Storage paths, then writes each product's own `ar*`
// Firestore fields — the local registration (`RoomArProductManifest` /
// `kRoomArProductMetadata` / `storage.rules`) already treats these 26 ids as
// fully specified; this tool is what actually makes them LIVE. Scoped
// EXCLUSIVELY to the 26 Phase 9.2 coverage-expansion ids — never touches the
// original four products (those are `scripts/upload_ar_models/` +
// `scripts/migrate_ar_catalogue/`'s domain).
//
// Usage:
//   node rollout_ar_coverage_expansion.mjs
//     Dry run (default). Preflights all six source files (SHA-256 exact) and
//     all 26 Storage + Firestore destinations, prints a READY/SKIP/BLOCK line
//     per product, performs NO writes.
//
//   node rollout_ar_coverage_expansion.mjs --apply --project=twin-ar-d4d75 --confirm-expansion-rollout
//     Live run. Refuses to start unless --project is EXACTLY "twin-ar-d4d75"
//     AND --confirm-expansion-rollout is passed. Aborts the whole run (zero
//     writes) if ANY of the 26 has a blocking problem (missing/mismatched
//     source, a conflicting Storage object, a missing/wrong-type/already-
//     different-ar*-contract Firestore document). Otherwise, product by
//     product: create-only Storage upload, then a single-document Firestore
//     transaction that re-checks the document hasn't drifted since the
//     preflight before writing only its `ar*` fields. Writes
//     backups/backup-<timestamp>.json (rollback inventory) and
//     results/rollout-<timestamp>.json (full report).
//
//   node rollout_ar_coverage_expansion.mjs --rollback=backups/<file>.json [--apply --project=twin-ar-d4d75]
//     Restores (dry run by default) exactly the `ar*` fields this rollout
//     wrote, per product, only for a document still in the exact state this
//     tool left it in.
//
// Requires GOOGLE_APPLICATION_CREDENTIALS / `gcloud auth application-default
// login`, exactly as scripts/seed_products/README.md describes.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';

import {
  CONFIRMED_PROJECT_ID,
  applyRollback,
  applyRollout,
  assertExpansionConfirmed,
  assertProjectGuard,
  buildRolloutPlan,
  summarizePlan,
} from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// scripts/rollout_ar_coverage_expansion -> scripts -> twin_ar -> Project_P2
// (workspace root, the parent that also contains _ar_assets).
const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const RESULTS_DIR = path.join(__dirname, 'results');
const BACKUP_DIR = path.join(__dirname, 'backups');

function parseArgs(argv) {
  const apply = argv.includes('--apply');
  const confirmed = argv.includes('--confirm-expansion-rollout');
  const projectArg = argv.find((a) => a.startsWith('--project='));
  const project = projectArg ? projectArg.slice('--project='.length) : null;
  const rollbackArg = argv.find((a) => a.startsWith('--rollback='));
  const rollbackFile = rollbackArg ? rollbackArg.slice('--rollback='.length) : null;
  let mode;
  if (rollbackFile) mode = apply ? 'rollback-apply' : 'rollback-dry-run';
  else mode = apply ? 'apply' : 'dry-run';
  return { mode, project, confirmed, rollbackFile };
}

function makeStorageAdapter(bucket) {
  return {
    async getMetadata(objectPath) {
      const file = bucket.file(objectPath);
      const [exists] = await file.exists();
      if (!exists) return { exists: false };
      const [meta] = await file.getMetadata();
      return {
        exists: true,
        md5Base64: meta.md5Hash ?? null,
        size: meta.size ?? null,
        contentType: meta.contentType ?? null,
        cacheControl: meta.cacheControl ?? null,
        generation: meta.generation ?? null,
        metadata: meta.metadata ?? {},
      };
    },
    async upload(objectPath, buffer, opts) {
      const file = bucket.file(objectPath);
      await file.save(buffer, {
        resumable: false,
        preconditionOpts: { ifGenerationMatch: opts.ifGenerationMatch },
        metadata: {
          contentType: opts.contentType,
          cacheControl: opts.cacheControl,
          metadata: opts.metadata,
        },
      });
      const [meta] = await file.getMetadata();
      return { generation: meta.generation ?? null };
    },
  };
}

const productRef = (db, id) => db.collection('products').doc(id);

function makeFirestoreAdapter(db) {
  return {
    async getProduct(id) {
      const snap = await productRef(db, id).get();
      return {
        data: snap.exists ? snap.data() : null,
        updateTime: snap.exists ? snap.updateTime.valueOf() : null,
      };
    },
    /** Writes `fields` onto `id` inside a transaction that re-verifies the
     *  document's updateTime hasn't moved since the preflight read — refuses
     *  (throws) rather than silently overwriting a doc someone else changed
     *  in the meantime. */
    async writeArFieldsIfUnchanged(id, fields, expectedUpdateTimeMs) {
      await db.runTransaction(async (tx) => {
        const ref = productRef(db, id);
        const snap = await tx.get(ref);
        if (!snap.exists) {
          throw new Error(`document ${id} no longer exists`);
        }
        const actualMs = snap.updateTime.valueOf();
        if (actualMs !== expectedUpdateTimeMs) {
          throw new Error(
            `document ${id} changed since preflight (updateTime drift) — refusing to write`,
          );
        }
        const current = snap.data();
        if (current.arModelStoragePath != null && current.arModelStoragePath !== '') {
          throw new Error(
            `document ${id} already carries arModelStoragePath — refusing to overwrite`,
          );
        }
        tx.update(ref, fields);
      });
    },
    /** Deletes exactly `keys` from `id`'s document, but ONLY when its current
     *  `arModelStoragePath` still matches what this tool would have written
     *  (i.e. nothing has changed it since) — never force-restores over a
     *  later, unrelated edit. */
    async deleteArFieldsIfWrittenByUs(id, keys) {
      await db.runTransaction(async (tx) => {
        const ref = productRef(db, id);
        const snap = await tx.get(ref);
        if (!snap.exists) throw new Error(`document ${id} no longer exists`);
        const data = snap.data();
        const expectedPath = `products/${id}/ar/model-v1.glb`;
        if (data.arModelStoragePath !== expectedPath) {
          throw new Error(
            `document ${id}'s arModelStoragePath no longer matches this rollout's ` +
              'write — will not roll back a value it did not write',
          );
        }
        const clears = {};
        for (const k of keys) clears[k] = admin.firestore.FieldValue.delete();
        tx.update(ref, clears);
      });
    },
  };
}

function writeJson(dir, prefix, payload) {
  mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(dir, `${prefix}-${stamp}.json`);
  writeFileSync(filePath, JSON.stringify(payload, null, 2));
  return filePath;
}

async function runRollout(args, storageAdapter, firestoreAdapter) {
  const plan = await buildRolloutPlan(storageAdapter, firestoreAdapter, WORKSPACE_ROOT);
  for (const line of summarizePlan(plan)) console.log(line);

  if (args.mode === 'dry-run') {
    console.log('');
    console.log(
      `No writes were made. Re-run with --apply --project=${CONFIRMED_PROJECT_ID} ` +
        '--confirm-expansion-rollout to perform the live rollout.',
    );
    return;
  }

  if (plan.abort) {
    console.error('\nAborting: the plan has blocking problems (see above). Zero writes.');
    process.exit(1);
  }
  if (plan.readyCount === 0) {
    console.log('\nNothing to roll out — all 26 already fully rolled out.');
    return;
  }

  console.log('\n--- Rolling out ---');
  const report = await applyRollout(plan, storageAdapter, firestoreAdapter);
  for (const u of report.uploaded) {
    console.log(`  UPLOAD ${u.productId} -> ${u.destPath} (gen ${u.generation})`);
  }
  for (const w of report.written) {
    console.log(`  WRITE  ${w.productId} ar* fields`);
  }
  for (const s of report.skipped) {
    console.log(`  SKIP   ${s.productId}`);
  }
  for (const f of report.failed) {
    console.log(`  FAIL   ${f.productId}: ${f.error}`);
  }

  const backupPath = writeJson(BACKUP_DIR, 'backup', report.backup);
  const resultsPath = writeJson(RESULTS_DIR, 'rollout', report);
  console.log(`\nBackup (for rollback): ${backupPath}`);
  console.log(`Full report: ${resultsPath}`);
  if (report.failed.length > 0) {
    console.log(
      `\n${report.failed.length} product(s) failed — safe to re-run this same ` +
        'command; already-correct products are skipped, not retried.',
    );
    process.exit(1);
  }
}

async function runRollback(args, firestoreAdapter) {
  const backup = JSON.parse(readFileSync(args.rollbackFile, 'utf8'));
  console.log(
    `--- Rollback ${args.mode === 'rollback-apply' ? '(LIVE)' : '(DRY RUN)'}: ${args.rollbackFile} ---`,
  );
  console.log(
    `schemaVersion: ${backup.schemaVersion}   entries: ${backup.entries?.length ?? 0}`,
  );
  for (const e of backup.entries ?? []) {
    console.log(`  - ${e.productId}: restore [${(e.writtenKeys ?? []).join(', ')}]`);
  }
  if (args.mode !== 'rollback-apply') {
    console.log(`\nDry run only. Add --apply --project=${CONFIRMED_PROJECT_ID} to restore.`);
    return;
  }
  const result = await applyRollback(backup, firestoreAdapter);
  for (const r of result.restored) console.log(`  OK    ${r.productId} restored`);
  for (const s of result.skipped) console.log(`  SKIP  ${s.productId}: ${s.reason}`);
  if (result.skipped.length > 0) process.exit(1);
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  try {
    assertProjectGuard(args.mode, args.project);
    assertExpansionConfirmed(args.mode, args.confirmed);
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: CONFIRMED_PROJECT_ID,
    storageBucket: `${CONFIRMED_PROJECT_ID}.firebasestorage.app`,
  });
  const db = admin.firestore();
  const firestoreAdapter = makeFirestoreAdapter(db);
  const storageAdapter = makeStorageAdapter(admin.storage().bucket());

  if (args.rollbackFile) {
    await runRollback(args, firestoreAdapter);
  } else {
    await runRollout(args, storageAdapter, firestoreAdapter);
  }
}

main().catch((err) => {
  if (String(err?.message ?? err).includes('Could not load the default credentials')) {
    console.error(
      'No Google credentials found. Run `gcloud auth application-default login` ' +
        '(or set GOOGLE_APPLICATION_CREDENTIALS), exactly as ' +
        'scripts/seed_products/README.md describes — the same credential works ' +
        'for every script in scripts/.',
    );
    process.exit(1);
  }
  console.error('Rollout failed:', err);
  process.exit(1);
});
