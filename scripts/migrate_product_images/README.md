# Product catalogue image migration (Phase 8.7.1) — manual procedure

**Status: the initial catalogue migration has already run and completed
successfully** (51 products migrated, 293 `asset` references converted to
`network`, 58 Storage objects uploaded, 0 failures, backup created,
migrated images physically verified in the app). The instructions below
remain the correct procedure for any future rerun (e.g. if new products
with bundled-asset images are added later) — dry-run first, then `--apply`,
with rollback always available from the backup that run produced.

Migrates real catalogue product images out of APK-bundled assets and into
Firebase Storage, so the shipped app doesn't need to bundle product photos
just to display them. Developer-only, local-only — not Flutter app code, not
a Cloud Function, not reachable from the mobile app. Uses the Firebase Admin
SDK, exactly like `scripts/seed_products/` and `scripts/super_admin_bootstrap/`
(bypasses `firestore.rules`/`storage.rules` entirely — same reason those
scripts do).

## Scope

Migrates **only** `ProductImageRef` entries with `source: "asset"` found on
the live Firestore `products/{id}`.`mainImage`/`.galleryMedia` fields.

Never touches:
- `source: "network"` entries (left byte-for-byte unchanged)
- `source: "file"` entries (should never exist in a committed Firestore doc;
  passed through unchanged defensively if one is ever found)
- logos, icons, onboarding/UI artwork, avatars
- `arModelAssetPath` / `vtoGarmentAssetPath` (AR/VTO assets)
- any other product field (title, price, stock, etc.)

## How it works

- Reads every document in the live `products` collection (not the static
  `products_seed.json` snapshot — Admin product edits since Phase 8.6 are
  real Firestore writes, so the live collection is the actual source of
  truth).
- For each `asset` reference, validates the local file (exists, `.jpg`/
  `.jpeg`/`.png`/`.webp` only, ≤10MB — the same limits `storage.rules`
  enforces for product images) and computes a **content-hash-based** object
  name: `products/{productId}/images/img-{sha256(bytes).slice(0,16)}{ext}`.
  Identical bytes always produce the same name **within one product's own
  path prefix** — this is what makes reruns idempotent (a matching object is
  reused, never re-uploaded) and collapses a single product's own repeated
  gallery references to the same source file into one uploaded object *for
  that product*. It is **not** a global, cross-product dedup: this
  catalogue's images are heavily reused (only 26 unique local files back
  293 pre-migration references, several shared across many different
  products), but because the object path includes `{productId}`, each
  product that uses a shared image still gets its own uploaded copy —
  confirmed by the live migration result of 58 Storage objects for 51
  products, not 26.
- **Per-product atomicity**: if *any* asset reference on a product fails
  validation, that whole product is skipped — none of its images are
  uploaded, its Firestore document is never touched. Only fully-valid
  products are migrated.
- Uploads happen before the Firestore write; the write happens only after
  every image that product needs has been uploaded or confirmed to already
  exist in Storage (`exists()` check — a matching object is reused, never
  re-uploaded). If the Firestore write then fails, only the object(s)
  created during that specific attempt are best-effort deleted; a
  previously-committed object is never touched.

## Usage

From `scripts/migrate_product_images/`:

```bash
npm install
```

### 1. Dry run (default — always do this first)

```bash
node migrate_product_images.mjs
```

Performs **no Firebase writes**. Reports:
- Products scanned
- Asset references found
- Already-network references skipped
- Documents that would change / that are blocked (with the specific
  missing/invalid file and reason) / that are already fully migrated
- Every planned Storage path

### 2. Live migration

```bash
node migrate_product_images.mjs --apply --project=twin-ar-d4d75
```

Refuses to run unless `--project` is **exactly** `twin-ar-d4d75` — a
copy-pasted command against the wrong project id is rejected before any
credential or write is attempted.

Before making any change, writes a timestamped backup to
`scripts/migrate_product_images/backups/backup-<timestamp>.json` containing
every affected product's `productId` and its original `mainImage`/
`galleryMedia` values. The path and the matching rollback command are
printed to the console.

Safe to re-run any time: already-migrated products (all-network) are
skipped, and already-uploaded objects are reused rather than duplicated.

### 3. Rollback

Preview (no writes):

```bash
node migrate_product_images.mjs --rollback=backups/backup-<timestamp>.json
```

Live restore — sets `mainImage`/`galleryMedia` back to the exact values
recorded in that backup file (their original `asset` references), on every
product listed in it:

```bash
node migrate_product_images.mjs --rollback=backups/backup-<timestamp>.json --apply --project=twin-ar-d4d75
```

This only restores the two Firestore fields; it does not delete the
Storage objects the migration created (harmless to leave behind, and the
same content-hash path will simply be reused if you re-migrate later).
Bundled assets are kept in `pubspec.yaml`/`assets/` for exactly this
purpose this phase — a rollback always has something to fall back to.

## Credentials

Same as `scripts/seed_products/README.md` step 2 — either
`gcloud auth application-default login` or a service-account key via
`GOOGLE_APPLICATION_CREDENTIALS`. No credentials or secrets are stored in
this directory or committed anywhere.

## Tests

```bash
npm test
```

Runs `lib.test.mjs` (Node's built-in test runner) against `lib.mjs`'s pure/
injectable logic — no real Firebase project or credentials needed. Covers:
dry-run reporting, idempotent reruns (no duplicate uploads/objects),
mixed asset/network galleries, missing/invalid files (whole-product block),
partial upload failure (rollback of only the newly-created object, both a
mid-upload failure and a post-upload Firestore-write failure), preservation
of the primary image / gallery order / alt text / unrelated fields, the
project-id guard, and backup/rollback round-tripping.

## Interaction with `scripts/seed_products/`

`seed_products.mjs` now merges its writes and skips the `mainImage`/
`galleryMedia` fields for any product that already has network-sourced
images, so re-seeding (e.g. to temporarily verify draft/inactive
visibility) can no longer silently restore old `asset` references over a
completed migration. See that script's own comments and
`--force-images` flag if you ever intentionally need the old
full-overwrite behavior.
