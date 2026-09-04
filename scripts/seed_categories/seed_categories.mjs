// TWin AR — category seed script (Phase 8.8).
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function,
// NOT reachable from the mobile app. Uses the Firebase Admin SDK, exactly
// like scripts/seed_products/ and scripts/migrate_product_images/ (bypasses
// firestore.rules/storage.rules entirely).
//
// Seeds the five canonical categories from categories_seed.json (regenerate
// via `dart run tool/export_category_seed.dart` from the repo root if the
// Dart seed data changes) - uploading each entry's bundled source image to
// Storage and creating its categories/{key} document, ONLY for documents
// that do not already exist. An existing document (from a prior run, or
// since edited by an Admin) is left completely untouched, unless --force is
// passed.
//
// Usage:
//   node seed_categories.mjs --confirm --project=twin-ar-d4d75
//     Creates any of the five category documents that do not yet exist.
//     Safe to re-run any time - existing documents (including any Admin
//     edits made since) are never touched.
//
//   node seed_categories.mjs --confirm --project=twin-ar-d4d75 --force
//     Also OVERWRITES all five documents back to their canonical seed
//     values, discarding any Admin edits made to them. Use deliberately,
//     never routinely.
//
// Requires GOOGLE_APPLICATION_CREDENTIALS / `gcloud auth application-default
// login`, exactly as scripts/seed_products/README.md describes.

import { readFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import admin from 'firebase-admin';

import { CONFIRMED_PROJECT_ID, assertProjectGuard, buildPublicUrl, runSeed } from './lib.mjs';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const REPO_ROOT = path.resolve(__dirname, '..', '..');
const SEED_FILE = path.join(__dirname, 'categories_seed.json');

function usageAndExit() {
  console.error(
    'Usage: node seed_categories.mjs --confirm --project=twin-ar-d4d75 [--force]',
  );
  console.error('');
  console.error('  --confirm   Required safety flag - the script refuses to run without it.');
  console.error(
    `  --project   Required - must be exactly "${CONFIRMED_PROJECT_ID}".`,
  );
  console.error(
    '  --force     Overwrite all five categories back to canonical seed values,',
  );
  console.error('              discarding any Admin edits made since. Use deliberately.');
  process.exit(1);
}

const args = process.argv.slice(2);
const confirmed = args.includes('--confirm');
const force = args.includes('--force');
const projectArg = args.find((a) => a.startsWith('--project='));
const project = projectArg ? projectArg.slice('--project='.length) : null;

if (!confirmed) {
  usageAndExit();
}

try {
  assertProjectGuard(project);
} catch (err) {
  console.error(err.message);
  process.exit(1);
}

let entries;
try {
  entries = JSON.parse(readFileSync(SEED_FILE, 'utf8'));
} catch (err) {
  console.error(
    `Could not read ${SEED_FILE}. Run "dart run tool/export_category_seed.dart" ` +
      'from the repo root first.',
  );
  console.error(err.message);
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: CONFIRMED_PROJECT_ID,
  storageBucket: `${CONFIRMED_PROJECT_ID}.firebasestorage.app`,
});

function makeFirestoreAdapter(db) {
  return {
    async getCategory(key) {
      const snap = await db.collection('categories').doc(key).get();
      return snap.exists ? snap.data() : null;
    },
    async createCategory(key, data) {
      await db.collection('categories').doc(key).set(data);
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
      await bucket.file(objectPath).save(buffer, { resumable: false, metadata: { contentType } });
    },
    async delete(objectPath) {
      await bucket.file(objectPath).delete();
    },
    publicUrl(objectPath) {
      return buildPublicUrl(bucket.name, objectPath);
    },
  };
}

async function main() {
  console.log(`Seeding categories to project "${CONFIRMED_PROJECT_ID}"...`);
  if (force) {
    console.log(
      '  --force passed: existing category documents WILL be overwritten back to canonical values.',
    );
  }

  const firestoreAdapter = makeFirestoreAdapter(admin.firestore());
  const storageAdapter = makeStorageAdapter(admin.storage().bucket());

  const results = await runSeed(entries, {
    repoRoot: REPO_ROOT,
    firestoreAdapter,
    storageAdapter,
    force,
  });

  let created = 0;
  let skipped = 0;
  let failed = 0;
  for (const r of results) {
    if (!r.ok) {
      failed++;
      console.log(`  FAIL    ${r.key}: ${r.reason}`);
    } else if (r.skipped) {
      skipped++;
      console.log(`  SKIP    ${r.key} (already exists — left untouched)`);
    } else {
      created++;
      console.log(`  ${r.forced ? 'REPLACED' : 'CREATED '} ${r.key} -> ${r.imageUrl}`);
    }
  }

  console.log('');
  console.log(
    `Done. ${created} created/replaced, ${skipped} skipped (already existed), ${failed} failed.`,
  );
  if (failed > 0) process.exitCode = 1;
}

main().catch((err) => {
  console.error('Seeding failed:', err);
  process.exit(1);
});
