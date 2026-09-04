// TWin AR — product catalog seed script (Phase 8.5).
//
// Developer-only, local-only. NOT Flutter app code, NOT a Cloud Function,
// NOT reachable from the mobile app. Bulk-writes the canonical product
// catalog (exported from the real MockCommerceDatabase seed data - the
// Dart source of truth - via `dart run tool/export_product_seed.dart`) to
// the live Firestore `products` collection using the Admin SDK, which
// bypasses `firestore.rules` entirely - the same reason
// scripts/super_admin_bootstrap/ uses the Admin SDK rather than the client
// SDK.
//
// Usage:
//   node seed_products.mjs --confirm
//     Upserts every product from products_seed.json exactly as exported
//     (published + active, per MockCommerceDatabase's canonical seed data).
//     Re-running this with no override flags always restores every
//     product to its canonical state - this IS the "revert" command
//     described below.
//
//   node seed_products.mjs --confirm --draft=<id1>,<id2> --inactive=<id3>
//     Same as above, but additionally forces publicationStatus to 'draft'
//     for the given product IDs, and/or isActive to false for the given
//     IDs, on top of the canonical seed. Use this ONLY to physically
//     verify that a draft/inactive product never leaks to a customer
//     session (Explore/Home/Product Details) but stays visible to Super
//     Admin - never to add permanent fake/synthetic data. Revert
//     immediately after by re-running with a plain `--confirm` (no
//     --draft/--inactive).
//
//   node seed_products.mjs --confirm --force-images
//     Same as the plain command, but ALSO overwrites mainImage/galleryMedia
//     back to this file's bundled-asset references, even for a product
//     Phase 8.7.1's migrate_product_images.mjs has already migrated to real
//     Storage URLs. Without this flag (the default, and the safe one), a
//     product whose mainImage.source is already 'network' has its
//     mainImage/galleryMedia fields left untouched by this script - every
//     other field still reseeds normally. This exists so a routine
//     draft/inactive-visibility check (see below) can never silently
//     regress a completed image migration back to bundled assets. Only
//     pass --force-images if you specifically intend to discard a
//     completed migration for the affected products.
//
//   node seed_products.mjs --confirm --force-category
//     Same as the plain command, but ALSO overwrites categoryId/
//     categoryKind back to this file's canonical seed values, even for a
//     product that already has either field set on the live document -
//     which, since Phase 8.8b, means a real Admin category assignment
//     (whether backfilled by migrate_product_categories.mjs or set by an
//     Admin editing/creating the product). Without this flag (the default,
//     and the safe one), a product with an existing categoryId/categoryKind
//     has BOTH fields left completely untouched by this script - every
//     other field still reseeds normally. This exists so a routine reseed
//     can never silently reset a live Admin category assignment back to
//     the canonical mock value. Only pass --force-category if you
//     specifically intend to discard a live category assignment.
//
// Requires GOOGLE_APPLICATION_CREDENTIALS / `gcloud auth application-default
// login`, exactly as scripts/super_admin_bootstrap/README.md describes -
// the same credential works for both scripts.

import { readFileSync } from 'fs';
import admin from 'firebase-admin';

const PROJECT_ID = 'twin-ar-d4d75';
const SEED_FILE = 'products_seed.json';

function usageAndExit() {
  console.error(
    'Usage: node seed_products.mjs --confirm [--draft=<id,...>] [--inactive=<id,...>] [--force-images] [--force-category]',
  );
  console.error('');
  console.error('  --confirm         Required safety flag - the script refuses to run without it.');
  console.error(
    '  --draft           Comma-separated product IDs to temporarily force to publicationStatus "draft".',
  );
  console.error(
    '  --inactive        Comma-separated product IDs to temporarily force isActive to false.',
  );
  console.error(
    '  --force-images    Also overwrite mainImage/galleryMedia for products already migrated to',
  );
  console.error(
    '                    real Storage URLs (Phase 8.7.1). Default: those two fields are left alone.',
  );
  console.error(
    '  --force-category  Also overwrite categoryId/categoryKind for products that already have a',
  );
  console.error(
    '                    live category assignment (Phase 8.8b). Default: both fields are left alone.',
  );
  console.error('');
  console.error(
    'Run with no --draft/--inactive to (re)seed every product to its canonical',
  );
  console.error(
    'state - this is also how you revert a temporary --draft/--inactive test.',
  );
  process.exit(1);
}

const args = process.argv.slice(2);
const confirmed = args.includes('--confirm');
const forceImages = args.includes('--force-images');
const forceCategory = args.includes('--force-category');
const draftArg = args.find((a) => a.startsWith('--draft='));
const inactiveArg = args.find((a) => a.startsWith('--inactive='));
const draftIds = new Set(
  draftArg ? draftArg.slice('--draft='.length).split(',').filter(Boolean) : [],
);
const inactiveIds = new Set(
  inactiveArg
    ? inactiveArg.slice('--inactive='.length).split(',').filter(Boolean)
    : [],
);

if (!confirmed) {
  usageAndExit();
}

let products;
try {
  products = JSON.parse(readFileSync(SEED_FILE, 'utf8'));
} catch (err) {
  console.error(
    `Could not read ${SEED_FILE}. Run "dart run tool/export_product_seed.dart" ` +
      'from the repo root first.',
  );
  console.error(err.message);
  process.exit(1);
}

const knownIds = new Set(products.map((p) => p.id));
for (const id of [...draftIds, ...inactiveIds]) {
  if (!knownIds.has(id)) {
    console.error(
      `--draft/--inactive references unknown product id "${id}" - not present ` +
        `in ${SEED_FILE}. Aborting - nothing was written.`,
    );
    process.exit(1);
  }
}

admin.initializeApp({
  credential: admin.credential.applicationDefault(),
  projectId: PROJECT_ID,
});

function toFirestoreDoc(product) {
  const { id, ...data } = product;
  data.addedDate = admin.firestore.Timestamp.fromDate(new Date(product.addedDate));
  if (draftIds.has(id)) {
    data.publicationStatus = 'draft';
  }
  if (inactiveIds.has(id)) {
    data.isActive = false;
  }
  return { id, data };
}

async function main() {
  console.log(`Seeding ${products.length} products to project "${PROJECT_ID}"...`);
  if (draftIds.size > 0) {
    console.log(`  TEMPORARY override: forcing draft on: ${[...draftIds].join(', ')}`);
  }
  if (inactiveIds.size > 0) {
    console.log(
      `  TEMPORARY override: forcing inactive on: ${[...inactiveIds].join(', ')}`,
    );
  }
  if (forceImages) {
    console.log(
      '  --force-images passed: mainImage/galleryMedia WILL be overwritten even for',
    );
    console.log(
      '  products already migrated to real Storage URLs (Phase 8.7.1).',
    );
  }
  if (forceCategory) {
    console.log(
      '  --force-category passed: categoryId/categoryKind WILL be overwritten even for',
    );
    console.log(
      '  products that already have a live category assignment (Phase 8.8b).',
    );
  }

  const db = admin.firestore();
  const collection = db.collection('products');

  // Read-before-write: a product already migrated to real Storage URLs
  // (mainImage.source !== 'asset') must not have mainImage/galleryMedia
  // silently reverted to this file's bundled-asset references by a routine
  // reseed - see the --force-images doc comment above. Same principle for
  // categoryId/categoryKind (Phase 8.8b) - either field already present
  // means a real category assignment exists and must be preserved.
  const refs = products.map((p) => collection.doc(p.id));
  const existingSnaps = refs.length > 0 ? await db.getAll(...refs) : [];
  const alreadyMigratedIds = new Set(
    existingSnaps
      .filter((snap) => snap.exists && snap.data()?.mainImage?.source !== 'asset')
      .map((snap) => snap.id),
  );
  const hasCategoryAssignmentIds = new Set(
    existingSnaps
      .filter((snap) => {
        const data = snap.data();
        return snap.exists && (data?.categoryId !== undefined || data?.categoryKind !== undefined);
      })
      .map((snap) => snap.id),
  );
  if (!forceImages && alreadyMigratedIds.size > 0) {
    console.log(
      `  Preserving migrated images on ${alreadyMigratedIds.size} product(s) (mainImage/galleryMedia left untouched).`,
    );
  }
  if (!forceCategory && hasCategoryAssignmentIds.size > 0) {
    console.log(
      `  Preserving category assignments on ${hasCategoryAssignmentIds.size} product(s) (categoryId/categoryKind left untouched).`,
    );
  }

  const batch = db.batch();
  for (const product of products) {
    const { id, data } = toFirestoreDoc(product);
    if (!forceImages && alreadyMigratedIds.has(id)) {
      delete data.mainImage;
      delete data.galleryMedia;
    }
    if (!forceCategory && hasCategoryAssignmentIds.has(id)) {
      delete data.categoryId;
      delete data.categoryKind;
    }
    // merge: true so omitting fields above leaves those fields exactly as
    // they already are in Firestore, instead of clearing them (a bare
    // `.set()` without merge would otherwise erase any field missing from
    // `data`).
    batch.set(collection.doc(id), data, { merge: true });
  }
  await batch.commit();

  console.log(`Done. ${products.length} products written.`);
  if (draftIds.size > 0 || inactiveIds.size > 0) {
    console.log('');
    console.log(
      'REMINDER: this run left a TEMPORARY draft/inactive override live on the',
    );
    console.log(
      'products above. Re-run with plain "--confirm" (no --draft/--inactive) once',
    );
    console.log('you are done verifying, to restore every product to its canonical state.');
  }
}

main().catch((err) => {
  console.error('Seeding failed:', err);
  process.exit(1);
});
