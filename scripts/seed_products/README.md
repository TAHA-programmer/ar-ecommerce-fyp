# Product catalog seed script (Phase 8.5) — manual procedure

Bulk-writes the canonical product catalog to the live Firestore `products`
collection. Developer-only, local-only — not Flutter app code, not a Cloud
Function, not deployed anywhere, not reachable from the mobile app. Uses
the Firebase Admin SDK, which bypasses `firestore.rules` entirely (same
reason `scripts/super_admin_bootstrap/` uses it).

The seed **data** is never hand-transcribed here: it comes from
`buildMockProductSeedData()` in
`lib/core/data/mock_product_seed_data.dart` — the same Dart source of truth
`MockCommerceDatabase` itself uses — exported to JSON by a small Dart tool.

## 1. Export the seed data from Dart

From the repo root:

```bash
dart run tool/export_product_seed.dart
```

This writes `scripts/seed_products/products_seed.json` (one JSON object
per seeded product, same field shape `firestore.rules`/
`FirestoreCommerceDatabase`/`productModelFromFirestore` expect). Re-run
this any time the Dart seed data changes so the exported file stays
current. (`products_seed.json` is generated output — safe to regenerate
any time, not meant to be hand-edited.)

## 2. Configure Firebase Admin credentials (local machine only)

Same as `scripts/super_admin_bootstrap/README.md` step 3 — either:

```bash
gcloud auth application-default login
```

or a service-account key via `GOOGLE_APPLICATION_CREDENTIALS`. See that
README for full detail; the same credential works for both scripts.

## 3. Seed the catalog

```bash
cd scripts/seed_products
npm install
node seed_products.mjs --confirm
```

Writes every product from `products_seed.json` to `products/{id}` on the
live `twin-ar-d4d75` project, exactly as `MockCommerceDatabase` defines
them (published + active, matching today's mock behavior). Safe to re-run
any time — every write is an upsert, so re-running always restores every
product to this canonical state.

## 4. (Optional) Temporarily verify draft/inactive visibility

Phase 8.5 physically verifies that a draft or inactive product never leaks
to a customer session (Explore/Home/Product Details) but is still visible
to Super Admin. The canonical seed products are all published + active by
default, so there's nothing to check that against out of the box — and no
permanent fake/synthetic product should be added to the real catalog just
to create one.

Instead, temporarily force one or two **real, existing** products to
draft/inactive through this same trusted script:

```bash
node seed_products.mjs --confirm --draft=boho-woven-rug
```

(or `--inactive=<id>`, or both, comma-separated for multiple IDs — any
product ID present in `products_seed.json`). Physically confirm on device:
the product disappears from Explore/Home/Product Details for a customer
session, but Super Admin still sees it (Product Management, Dashboard
counts, etc.).

**Revert immediately after** by re-running the plain command from step 3
(`node seed_products.mjs --confirm`, no `--draft`/`--inactive`) — this
restores every product, including the one just overridden, back to its
canonical published/active state. Do not leave a `--draft`/`--inactive`
override live in the project longer than the verification itself takes.

## Notes

- This script only ever writes to the `products` collection.
- Re-running the plain (no-override) command is always safe and always
  converges every product back to the canonical seed state.
- `firestore.rules`' `products` rule has `write: if false` this phase (no
  client, not even Super Admin, can write a product until Phase 8.6) — the
  Admin SDK used here bypasses that entirely, which is expected and is the
  whole reason this is a script rather than an in-app action.
