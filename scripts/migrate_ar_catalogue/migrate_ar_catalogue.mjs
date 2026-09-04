// TWin AR — Phase 9.2 R13/R14: Room-AR catalogue recast (CLI).
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function.
//
// Recasts the FOUR physically-approved Room-AR products' catalogue text
// (title / description / material + dimension specs), their production `ar*`
// metadata, and (sofa only) the verified customer gallery — in ONE genuine
// Firestore transaction. A preflight, concurrency or runtime failure leaves
// ALL four documents unchanged. Never `.set()`, never a reseed, never a
// delete of a document. Only explicitly controlled fields are written; price,
// stock, category, ownership, timestamps and unrelated media stay untouched.
//
// Usage:
//   node migrate_ar_catalogue.mjs
//     Dry run (default). Reads all four docs + the sofa gallery objects,
//     prints an exact before/after per product, performs ZERO writes.
//
//   node migrate_ar_catalogue.mjs --apply --project=twin-ar-d4d75 --dimensions-approved
//     Live run in one transaction. Refuses unless --project is EXACTLY
//     "twin-ar-d4d75" AND --dimensions-approved. Aborts (zero writes) if ANY
//     document is missing / has an unexpected or partially-migrated value, or
//     the sofa gallery objects are not staged.
//
//   node migrate_ar_catalogue.mjs --rollback=backups/<file>.json [--apply --project=twin-ar-d4d75]
//     Restore, in one transaction, exactly the fields this migration wrote —
//     and only when every document is still in the exact post-migration
//     state (updateTime + every written field). A later edit blocks it.
//
// Requires GOOGLE_APPLICATION_CREDENTIALS / `gcloud auth application-default
// login`.

import { mkdirSync, readFileSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';

import {
  CONFIRMED_PROJECT_ID,
  DELETE_FIELD,
  MigrationAbort,
  assertDimensionSignOff,
  assertProjectGuard,
  buildBackupPayload,
  buildFullPlan,
  commitRecast,
  commitRollback,
  finaliseBackup,
  requiredStorageObjects,
  summarizePlans,
  validateBackup,
} from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const BACKUP_DIR = path.join(__dirname, 'backups');

function parseArgs(argv) {
  const apply = argv.includes('--apply');
  const dimensionsApproved = argv.includes('--dimensions-approved');
  const projectArg = argv.find((a) => a.startsWith('--project='));
  const project = projectArg ? projectArg.slice('--project='.length) : null;
  const rollbackArg = argv.find((a) => a.startsWith('--rollback='));
  const rollbackFile = rollbackArg ? rollbackArg.slice('--rollback='.length) : null;
  let mode;
  if (rollbackFile) mode = apply ? 'rollback-apply' : 'rollback-dry-run';
  else mode = apply ? 'apply' : 'dry-run';
  return { mode, project, rollbackFile, dimensionsApproved };
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
  };
}

function makeStorageAdapter(bucket) {
  return {
    async statObject(objectPath) {
      const file = bucket.file(objectPath);
      const [exists] = await file.exists();
      if (!exists) return { exists: false };
      const [meta] = await file.getMetadata();
      return {
        exists: true,
        sizeBytes: meta.size != null ? Number(meta.size) : null,
        sha256: meta.metadata?.twinArSofaGallerySha256 ?? null,
        contentType: meta.contentType ?? null,
      };
    },
  };
}

/** A transaction-scoped adapter over a Firestore `Transaction`. */
function makeTxAdapter(db, tx) {
  const buffered = [];
  return {
    async get(id) {
      const snap = await tx.get(productRef(db, id));
      return {
        exists: snap.exists,
        data: snap.exists ? snap.data() : null,
        updateTime: snap.exists ? snap.updateTime.valueOf() : null,
      };
    },
    update(id, fields) {
      const translated = {};
      for (const [k, v] of Object.entries(fields)) {
        translated[k] = v === DELETE_FIELD ? admin.firestore.FieldValue.delete() : v;
      }
      buffered.push(id);
      tx.update(productRef(db, id), translated);
    },
    buffered,
  };
}

function describeChange(plan) {
  if (plan.status === 'already-recast') return `  SKIP  ${plan.productId} (already recast)`;
  if (plan.blocked) {
    const lines = [`  BLOCK ${plan.productId} (${plan.status})`];
    for (const d of plan.diagnostics ?? [plan.reason]) lines.push(`         - ${d}`);
    return lines.join('\n');
  }
  const lines = [`  RECAST ${plan.productId}`];
  for (const [k, v] of Object.entries(plan.write)) {
    const before = plan.before[k];
    const b = before === DELETE_FIELD ? '(absent)' : JSON.stringify(before);
    lines.push(`    ${k}:  ${b}  ->  ${JSON.stringify(v)}`);
  }
  return lines.join('\n');
}

function printDryRun(plans, storageVerification) {
  console.log('--- Phase 9.2 R13/R14 — Room-AR catalogue recast: DRY RUN ---');
  console.log('Sofa gallery Storage objects:');
  for (const p of requiredStorageObjects()) {
    const s = storageVerification[p];
    console.log(`  ${s?.exists ? 'present' : 'MISSING'}  ${p}${s?.exists ? ` (size ${s.sizeBytes}, sha ${(s.sha256 ?? '?').slice(0, 12)}…)` : ''}`);
  }
  console.log('');
  for (const plan of plans) console.log(describeChange(plan));
  const summary = summarizePlans(plans);
  console.log('');
  console.log(`Would change: ${summary.documentsThatWouldChange.length}   already recast: ${summary.alreadyRecast.length}   blocked: ${summary.blockers.length}`);
  if (summary.hasBlockers) {
    console.log('\nRUN BLOCKED — no write will happen:');
    for (const b of summary.blockers) console.log(`  - [${b.productId}] ${b.status}: ${b.reason}`);
  }
  console.log('\nNo Firebase writes were made.');
  return summary;
}

function writeBackupFile(backup) {
  mkdirSync(BACKUP_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(BACKUP_DIR, `backup-${stamp}.json`);
  writeFileSync(filePath, JSON.stringify(backup, null, 2));
  return filePath;
}

async function runRecast({ mode, dimensionsApproved }, db, firestore, storage) {
  const { plans, storageVerification } = await buildFullPlan(firestore, storage);
  const summary = printDryRun(plans, storageVerification);

  if (mode === 'dry-run') {
    console.log(`Re-run with --apply --project=${CONFIRMED_PROJECT_ID} --dimensions-approved to write.`);
    return;
  }

  assertDimensionSignOff('apply', dimensionsApproved); // already checked, belt-and-braces
  if (summary.hasBlockers) {
    console.error('\nAborting: blocking problems (see above). Zero writes.');
    process.exit(1);
  }
  const changing = plans.filter((p) => p.wouldChange);
  if (changing.length === 0) {
    console.log('\nNothing to recast — all four already correct.');
    return;
  }
  // The transaction re-checks EVERY target document (changing + already-final),
  // so drift in any of the four aborts the whole commit.
  const targetPlans = plans.filter(
    (p) => p.status === 'needs-recast' || p.status === 'already-recast',
  );

  // Backup the pre-apply state BEFORE the transaction, then finalise it after.
  const backup = buildBackupPayload(plans);
  const backupPath = writeBackupFile(backup);
  console.log(`\nBackup written: ${backupPath}`);

  console.log('\n--- Committing (one transaction) ---');
  let committedIds = [];
  try {
    committedIds = await db.runTransaction(
      async (tx) => {
        const txAdapter = makeTxAdapter(db, tx);
        return commitRecast(targetPlans, txAdapter, storageVerification);
      },
      { maxAttempts: 3 },
    );
  } catch (err) {
    if (err instanceof MigrationAbort) {
      console.error(`\nMigrationAbort: ${err.message}`);
      console.error('The transaction committed NOTHING. All four documents are unchanged.');
      process.exit(1);
    }
    throw err;
  }

  // Record the post-commit updateTimes into the backup so rollback is guarded.
  const post = {};
  for (const id of committedIds) {
    const snap = await productRef(db, id).get();
    post[id] = snap.updateTime.valueOf();
  }
  finaliseBackup(backup, post);
  writeFileSync(backupPath, JSON.stringify(backup, null, 2));

  console.log(`  OK — ${committedIds.length} document(s) recast in one transaction: ${committedIds.join(', ')}`);
  console.log(`\nRollback: node migrate_ar_catalogue.mjs --rollback=${backupPath} --apply --project=${CONFIRMED_PROJECT_ID}`);
}

async function runRollback({ mode }, db, rollbackFile) {
  const backup = JSON.parse(readFileSync(rollbackFile, 'utf8'));
  console.log(`--- Rollback ${mode === 'rollback-apply' ? '(LIVE, one transaction)' : '(DRY RUN)'}: ${rollbackFile} ---`);
  console.log(`schemaVersion: ${backup.schemaVersion}   entries: ${backup.entries?.length ?? 0}`);
  for (const e of backup.entries ?? []) {
    console.log(`  - ${e.productId}: restore [${(e.writtenKeys ?? []).join(', ')}]  (post-migration updateTime ${e.updateTimeAfterApply ?? 'MISSING'})`);
  }

  try {
    validateBackup(backup);
    console.log('  backup artifact: valid + finalised');
  } catch (err) {
    console.error(`  backup artifact: INVALID — ${err.message}`);
    if (mode !== 'rollback-apply') return;
    process.exit(1);
  }

  if (mode !== 'rollback-apply') {
    console.log(`\nDry run only. Add --apply --project=${CONFIRMED_PROJECT_ID} to restore.`);
    return;
  }

  try {
    const ids = await db.runTransaction(
      async (tx) => {
        const txAdapter = makeTxAdapter(db, tx);
        return commitRollback(backup, txAdapter);
      },
      { maxAttempts: 3 },
    );
    console.log(`\n  OK — rolled back ${ids.length} document(s) in one transaction: ${ids.join(', ')}`);
  } catch (err) {
    if (err instanceof MigrationAbort) {
      console.error(`\nMigrationAbort: ${err.message}`);
      console.error('The rollback transaction committed NOTHING.');
      process.exit(1);
    }
    throw err;
  }
}

async function main() {
  const args = parseArgs(process.argv.slice(2));
  try {
    assertProjectGuard(args.mode, args.project);
    assertDimensionSignOff(args.mode === 'apply' ? 'apply' : 'dry-run', args.dimensionsApproved);
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
  const firestore = makeFirestoreAdapter(db);
  const storage = makeStorageAdapter(admin.storage().bucket());

  if (args.rollbackFile) {
    await runRollback(args, db, args.rollbackFile);
  } else {
    await runRecast(args, db, firestore, storage);
  }
}

main().catch((err) => {
  if (String(err?.message ?? err).includes('Could not load the default credentials')) {
    console.error(
      'No Google credentials found. Run `gcloud auth application-default login` ' +
        '(or set GOOGLE_APPLICATION_CREDENTIALS), as scripts/seed_products/README.md describes.',
    );
    process.exit(1);
  }
  console.error('Recast failed:', err);
  process.exit(1);
});
