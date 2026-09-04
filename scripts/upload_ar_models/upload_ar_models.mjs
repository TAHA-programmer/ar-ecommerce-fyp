// TWin AR — Phase 9.2 R10: Room-AR GLB upload tool (CLI).
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function,
// NOT reachable from the mobile app — mirrors scripts/migrate_product_images/
// and scripts/seed_products/'s Admin SDK pattern (bypasses storage.rules
// entirely, same reason those scripts do).
//
// Uploads exactly the four physically-approved Room-AR GLBs to their
// versioned Storage object paths:
//   products/{productId}/ar/model-v1.glb
// and nothing else. Never writes Firestore, never deletes a Storage object,
// never runs the seed script.
//
// Usage:
//   node upload_ar_models.mjs
//     Dry run (default). Preflights all four source files (SHA-256 exact) and
//     all four destinations, prints an UPLOAD/SKIP/BLOCK line per product, and
//     performs NO writes.
//
//   node upload_ar_models.mjs --apply --project=twin-ar-d4d75
//     Live upload. Refuses to start unless --project is EXACTLY
//     "twin-ar-d4d75". Aborts the whole run (zero uploads) if any source is
//     missing/mismatched or any destination already holds different bytes.
//     Uploads only absent objects, create-only (ifGenerationMatch: 0), and
//     writes results/upload-<timestamp>.json (report + rollback inventory).
//
// Requires GOOGLE_APPLICATION_CREDENTIALS / `gcloud auth application-default
// login`, exactly as scripts/seed_products/README.md describes.

import { mkdirSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';

import {
  CONFIRMED_PROJECT_ID,
  applyUpload,
  assertProjectGuard,
  buildUploadPlan,
  summarizePlan,
} from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// scripts/upload_ar_models -> scripts -> twin_ar -> Project_P2 (workspace root,
// the parent that also contains _ar_assets).
const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const RESULTS_DIR = path.join(__dirname, 'results');

function parseArgs(argv) {
  const apply = argv.includes('--apply');
  const projectArg = argv.find((a) => a.startsWith('--project='));
  const project = projectArg ? projectArg.slice('--project='.length) : null;
  return { mode: apply ? 'apply' : 'dry-run', project };
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

function writeResults(report) {
  mkdirSync(RESULTS_DIR, { recursive: true });
  const stamp = new Date().toISOString().replace(/[:.]/g, '-');
  const filePath = path.join(RESULTS_DIR, `upload-${stamp}.json`);
  writeFileSync(filePath, JSON.stringify(report, null, 2));
  return filePath;
}

async function main() {
  const { mode, project } = parseArgs(process.argv.slice(2));
  try {
    assertProjectGuard(mode, project);
  } catch (err) {
    console.error(err.message);
    process.exit(1);
  }

  admin.initializeApp({
    credential: admin.credential.applicationDefault(),
    projectId: CONFIRMED_PROJECT_ID,
    storageBucket: `${CONFIRMED_PROJECT_ID}.firebasestorage.app`,
  });
  const storageAdapter = makeStorageAdapter(admin.storage().bucket());

  const plan = await buildUploadPlan(storageAdapter, WORKSPACE_ROOT);
  for (const line of summarizePlan(plan)) console.log(line);

  if (mode === 'dry-run') {
    console.log('');
    console.log(
      `No writes were made. Re-run with --apply --project=${CONFIRMED_PROJECT_ID} ` +
        'to perform the live upload.',
    );
    return;
  }

  if (plan.abort) {
    console.error('\nAborting: the plan has blocking problems (see above).');
    process.exit(1);
  }
  if (plan.toCreateCount === 0) {
    console.log('\nNothing to upload — every object already correct.');
    return;
  }

  console.log('\n--- Uploading ---');
  const report = await applyUpload(plan, storageAdapter);
  for (const c of report.created) {
    console.log(`  OK   ${c.productId} -> ${c.destPath} (gen ${c.generation})`);
  }
  for (const s of report.skipped) {
    console.log(`  SKIP ${s.productId} -> ${s.destPath}`);
  }
  for (const f of report.failed) {
    console.log(`  FAIL ${f.productId} -> ${f.destPath}: ${f.error}`);
  }
  const resultsPath = writeResults(report);
  console.log(`\nReport + rollback inventory: ${resultsPath}`);
  if (report.failed.length > 0) process.exit(1);
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
  console.error('Upload failed:', err);
  process.exit(1);
});
