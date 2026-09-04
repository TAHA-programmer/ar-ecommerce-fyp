# Category seed script (Phase 8.8) — manual procedure

Seeds the five canonical categories (`furniture`, `clothing`, `rugs`,
`decor`, `lighting`) to the live Firestore `categories` collection,
uploading each one's bundled source image to Firebase Storage first.
Developer-only, local-only — not Flutter app code, not a Cloud Function, not
reachable from the mobile app. Uses the Firebase Admin SDK, exactly like
`scripts/seed_products/` and `scripts/migrate_product_images/`.

**Status: not yet run against the live project.** `firestore.rules`/
`storage.rules` are also not yet deployed — see the top-level implementation
report for what's still outstanding before this can be run for real.

## 1. Export the seed data from Dart

From the repo root:

```bash
dart run tool/export_category_seed.dart
```

Writes `scripts/seed_categories/categories_seed.json` from
`buildCategorySeedData()` in `lib/core/data/category_seed_data.dart` — the
single Dart source of truth. Re-run this any time that file changes.

## 2. Configure Firebase Admin credentials

Same as `scripts/seed_products/README.md` step 2 — either
`gcloud auth application-default login` or a service-account key via
`GOOGLE_APPLICATION_CREDENTIALS`.

## 3. Seed the categories

```bash
cd scripts/seed_categories
npm install
node seed_categories.mjs --confirm --project=twin-ar-d4d75
```

Refuses to run unless `--project` is **exactly** `twin-ar-d4d75`. For each
of the five categories: validates its source image, uploads it to
`categories/{key}/images/img-{contentHash}.{ext}` (reusing the object if a
matching one already exists — idempotent), and creates the Firestore
document — **but only if that document does not already exist**. A document
that already exists (from a prior run, or since edited by an Admin through
the app — a renamed category, a re-uploaded image, a different active
status) is left **completely untouched**. Safe to re-run any time.

## 4. (Rare) Force-reset to canonical values

```bash
node seed_categories.mjs --confirm --project=twin-ar-d4d75 --force
```

Overwrites all five documents back to their canonical seed values,
**discarding any Admin edits made to them since**. Use deliberately, never
as part of a routine reseed.

## Notes

- This script only ever writes to the `categories` collection, and only the
  five canonical documents (`furniture`/`clothing`/`rugs`/`decor`/
  `lighting`) — it never touches a category an Admin created through the
  app.
- Every write is validated/uploaded before the corresponding document is
  created — a bad or missing source image aborts that one entry (reported,
  not silently skipped) without touching Firestore or Storage for it; the
  other four entries are unaffected.
- If a Firestore document create fails after a new image upload, only that
  newly-created object is rolled back (best-effort) — never a pre-existing
  one.
- `--confirm` is required; the script refuses to run without it. No
  credentials or secrets are stored in this directory or committed anywhere.

## Tests

```bash
npm test
```

Runs `lib.test.mjs` against `lib.mjs`'s pure/injectable logic — no real
Firebase project or credentials needed.
