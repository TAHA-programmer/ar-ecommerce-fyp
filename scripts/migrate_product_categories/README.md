# Product category reference backfill (Phase 8.8b) — manual procedure

**Status: LIVE MIGRATION COMPLETE, PHYSICALLY APPROVED.** Written as part of
the Phase 8.8b implementation (the app code ships with a dual-read fallback
so it works correctly with or without this script having run — see
`product_firestore_mapper.dart`). `--apply` has been run against the live
`twin-ar-d4d75` project: an initial dry run scanned 51 products (0 already
migrated, 51 requiring changes, 0 blockers), then the live apply succeeded,
creating its automatic pre-write backup. Post-migration verification and
Android physical testing passed — see `09_BACKEND_INTEGRATION_PLAN.md` →
"Phase 8.8b — Live Backfill & Physical Approval" for the full record. This
document's procedure below remains accurate for any future re-run (e.g. if
new legacy-shaped products are ever introduced) and is safe to re-run any
time, since already-migrated products are recognized and skipped.

Backfills `categoryId`/`categoryKind` onto live `products/{id}` documents
that still only carry the legacy `category` field, matching it against a
real `categories/{categoryId}` document. Developer-only, local-only — not
Flutter app code, not a Cloud Function, not reachable from the mobile app.
Uses the Firebase Admin SDK, exactly like `scripts/migrate_product_images/`
and `scripts/seed_products/` (bypasses `firestore.rules` entirely — same
reason those scripts do).

## Scope

Reads and writes **only** `categoryId`/`categoryKind` on `products/{id}`.
Never touches `mainImage`/`galleryMedia`/price/stock/anything else — every
write is a narrow `.update({ categoryId, categoryKind })`, never a `.set()`.
The legacy `category` field itself is never deleted by this script (it's
harmless to leave — the app's dual-read prefers the new fields when
present, and a normal Admin edit will naturally drop it later via
`updateProduct`'s full-document overwrite).

## All-or-nothing safety model

Unlike `scripts/migrate_product_images/` (which migrates each product
independently, skipping/reporting the ones that fail), this tool validates
**every** product before writing **anything**:

- A product's legacy `category` value must be one of the five known
  categories.
- The matching `categories/{categoryId}` document must actually exist, and
  its `kind` must match.
- A product with only one of `categoryId`/`categoryKind` set, or with
  values inconsistent with the real category document, is flagged
  **partially migrated** — never silently "fixed" by guessing.

If validation finds **any** blocker anywhere in the collection, `--apply`
aborts completely with **zero writes** and prints every blocker. Fix the
flagged documents (or decide how to handle them) and re-run — a single
execution can never leave the live dataset partially migrated.

## Usage

From `scripts/migrate_product_categories/`:

```bash
npm install
```

### 1. Dry run (default — always do this first)

```bash
node migrate_product_categories.mjs
```

Performs **no Firebase writes**. Reports products scanned, how many are
already migrated, which documents would change, and every blocker with its
exact reason (`invalid-legacy-category`, `category-doc-missing`,
`kind-mismatch`, or `partially-migrated`).

### 2. Live migration

```bash
node migrate_product_categories.mjs --apply --project=twin-ar-d4d75
```

Refuses to run unless `--project` is **exactly** `twin-ar-d4d75`. Refuses
to write anything if the validation pass found any blocker (see above).
Only once validation is fully clean does it write a timestamped backup —
`scripts/migrate_product_categories/backups/backup-<timestamp>.json` —
capturing, for every product that will change, the **exact original
presence and value** of `categoryId`/`categoryKind` (whether each field
existed at all, not just its value), *before* the first Firebase write.
The path and the matching rollback command are printed to the console.

Safe to re-run any time: already-migrated products (whether migrated by
this script or by a normal Admin edit) are recognized and skipped.

### 3. Rollback

Preview (no writes):

```bash
node migrate_product_categories.mjs --rollback=backups/backup-<timestamp>.json
```

Live restore — for every product in the backup, restores `categoryId`/
`categoryKind` to their **exact original state**: if a field didn't exist
before this script touched it, rollback deletes it entirely (never leaves
a stray value); if it did exist, rollback restores its exact prior value:

```bash
node migrate_product_categories.mjs --rollback=backups/backup-<timestamp>.json --apply --project=twin-ar-d4d75
```

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
every plan status (already-migrated, needs-migration, and each blocker
kind), exact-state backup capture, narrow-write-only application, exact
rollback (including field deletion when a field never existed), and the
project-id guard.

## Interaction with `scripts/seed_products/`

`seed_products.mjs` preserves an existing product's `categoryId`/
`categoryKind` on a routine reseed (mirroring how it already preserves
migrated `mainImage`/`galleryMedia`) unless `--force-category` is passed —
so re-seeding never resets a live Admin category assignment, whether it
got there via this backfill script or a normal product edit. See that
script's own comments.
