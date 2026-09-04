// TWin AR — Phase 9.2 R14 Stage A: sofa customer-gallery uploader (CLI).
//
// Developer-only, local-only. Uploads the six approved Luna Right-Chaise
// Sectional Sofa studio renders to
//   products/luna-3-seater-sofa/images/img-<sha16>.png
// and NOTHING else. Never writes Firestore, never deletes, never runs a seed.
// Uploading these images does not modify the customer catalogue — the
// catalogue recast (../migrate_ar_catalogue/) does that, only after
// re-verifying every object.
//
// Usage:
//   node upload_sofa_gallery.mjs
//     Dry run (default). Preflights the six renders (SHA-256 + size exact,
//     PNG magic) and the six destinations. Zero writes.
//
//   node upload_sofa_gallery.mjs --apply --project=twin-ar-d4d75
//     Live upload. Refuses unless --project is EXACTLY "twin-ar-d4d75".
//     Aborts the whole run if any render is missing/mismatched or any
//     destination already holds different bytes. Create-only
//     (ifGenerationMatch: 0). Writes results/upload-<timestamp>.json.

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
import { SOFA_SHA256_METADATA_KEY, STORAGE_BUCKET } from './sofa_gallery.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
// scripts/upload_sofa_gallery -> scripts -> twin_ar -> Project_P2
const WORKSPACE_ROOT = path.resolve(__dirname, '..', '..', '..');
const RESULTS_DIR = path.join(__dirname, 'results');

function parseArgs(argv) {
  const apply = argv.includes('--apply');
  const projectArg = argv.find((a) => a.startsWith('--project='));
  return {
    mode: apply ? 'apply' : 'dry-run',
    project: projectArg ? projectArg.slice('--project='.length) : null,
  };
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
        sha256Meta: meta.metadata?.[SOFA_SHA256_METADATA_KEY] ?? null,
        generation: meta.generation ?? null,
      };
    },
    async upload(objectPath, buffer, opts) {
      const file = bucket.file(objectPath);
      await file.save(buffer, {
        resumable: false,
        preconditionOpts: { ifGenerationMatch: opts.ifGenerationMatch },
        metadata: { contentType: opts.contentType, metadata: opts.metadata },
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
    storageBucket: STORAGE_BUCKET,
  });
  const storageAdapter = makeStorageAdapter(admin.storage().bucket());

  const plan = await buildUploadPlan(storageAdapter, WORKSPACE_ROOT);
  for (const line of summarizePlan(plan)) console.log(line);

  if (mode === 'dry-run') {
    console.log(
      `\nNo writes were made. Re-run with --apply --project=${CONFIRMED_PROJECT_ID} to upload.`,
    );
    return;
  }
  if (plan.abort) {
    console.error('\nAborting: the plan has blocking problems (see above).');
    process.exit(1);
  }
  if (plan.toCreateCount === 0) {
    console.log('\nNothing to upload — every render already byte-identical in Storage.');
    return;
  }

  console.log('\n--- Uploading ---');
  const report = await applyUpload(plan, storageAdapter);
  for (const c of report.created) console.log(`  OK   ${c.objectPath} (gen ${c.generation})`);
  for (const s of report.skipped) console.log(`  SKIP ${s.objectPath}`);
  for (const f of report.failed) console.log(`  FAIL ${f.objectPath}: ${f.error}`);
  const resultsPath = writeResults(report);
  console.log(`\nReport + rollback inventory: ${resultsPath}`);
  if (report.failed.length > 0) process.exit(1);
}

main().catch((err) => {
  if (String(err?.message ?? err).includes('Could not load the default credentials')) {
    console.error(
      'No Google credentials found. Run `gcloud auth application-default login` ' +
        '(or set GOOGLE_APPLICATION_CREDENTIALS), as scripts/seed_products/README.md describes.',
    );
    process.exit(1);
  }
  console.error('Upload failed:', err);
  process.exit(1);
});
