# Legacy AR field audit (Phase 9.2 R20) — read-only, manual procedure

Answers whether any live `products` document still carries a **genuine
legacy** top-level `arModelAssetPath` or `arScale` value — one with no
current Room-AR contract behind it.

**Important correction (2026-09-09, after the first live run):** `arScale`
is not purely legacy. `ProductArMetadata.toFirestoreFields()` (the CURRENT,
valid Room-AR metadata contract) unconditionally writes the **same
Firestore key**, `arScale`, whenever a product has a real contract
(`arMetadata != null`) — independently of the legacy top-level Dart field —
and `ProductFirestoreMapper` applies that write *after* the legacy one, so
it wins. So a non-null live `arScale` on a document that also has
`arModelStoragePath` set (the marker of a real contract) is the current
contract's own authoritative value, not legacy drift, and keeps being
written correctly regardless of whether the legacy Dart field exists. Only
a non-null `arScale` with **no** `arModelStoragePath` — or any non-null
`arModelAssetPath`, which nothing modern ever writes — is a genuine legacy
value. The script and the Console steps below now distinguish the two.

This is the exact blocker recorded against R20 in
`16_PHASE_9_2_ROOM_AR_TRACKER.md` §33.6/§34.2/§35 and
`18_ROOM_AR_PRODUCT_COVERAGE_MATRIX.md`: `ProductFirestoreMapper` still
writes the legacy `arModelAssetPath`/`arScale` keys on every full `.set()`
(preserving whatever value was already there — by design, so an existing
value survives a read). If the two legacy Dart model fields were removed
without checking this first, the next ordinary admin edit+save of any
document that still has a **genuine** legacy value set (no contract behind
it) would silently strip it from that live document. A document whose
`arScale` is explained by a live contract is unaffected either way.

**Two equally safe, read-only ways to check — pick whichever is easier.**
Neither writes, deletes, or touches Storage.

## Option A — Firebase Console (no local setup needed)

1. Open <https://console.firebase.google.com/project/twin-ar-d4d75/firestore/data/products>
   (or navigate: your project → Firestore Database → Data tab → `products`).
2. Click the **Filter** icon above the document list.
3. Add a filter: field `arModelAssetPath`, condition "is not null" (or, if
   the console you're using only offers `!=`, use `!=` with an empty/blank
   value — either finds any document where the field is actually set).
4. Note the result count and ids — nothing modern writes `arModelAssetPath`,
   so any hit here is genuine legacy data.
5. Repeat with field `arScale`, "is not null". For each matching product id,
   also check whether that same document has `arModelStoragePath` set (add
   it as a second filter, or open the document and look). A hit with
   `arModelStoragePath` also set is the **current contract's own value, not
   legacy drift** — safe. A hit with `arScale` set but **no**
   `arModelStoragePath` is a genuine legacy value.
6. Removing the legacy Dart fields is safe once `arModelAssetPath` is empty
   everywhere and every remaining `arScale` hit has `arModelStoragePath`
   alongside it. Otherwise, note the genuine legacy product id(s) and stop —
   do not remove the fields yet.

This is pure browsing/filtering in the Console's own UI — nothing is
written.

## Option B — the script in this folder (PowerShell or any shell)

Needs the same Firebase Admin credential every other script in `scripts/`
already needs — see `../migrate_ar_catalogue/README.md` step 3 for the full
explanation. In short, either:

```bash
gcloud auth application-default login
```

or set `GOOGLE_APPLICATION_CREDENTIALS` to a service-account key path.

Then, from the repo root:

```bash
cd scripts/audit_legacy_ar_fields
npm install
npm run audit
```

This performs **only** `products.get()` reads and prints:
- total products inspected,
- every product id (if any) with a non-null `arModelAssetPath` (always
  genuine legacy — nothing modern writes this key),
- every product id (if any) with a non-null `arScale`, each labelled either
  `[has arModelStoragePath — current contract value, NOT legacy drift]` or
  `[NO arModelStoragePath — genuine legacy value]`,
- a plain-English RESULT line saying whether removal is safe, based only on
  the genuine-legacy count.

Safe to run any number of times — there is no `--apply`/`--confirm` flag
because there is nothing in this script that could ever write anything.

## What to do with the result

- **Zero matches on both fields:** removing `ProductModel.arModelAssetPath`
  / `ProductModel.arScale` (the class fields, their `copyWith` params, and
  `ProductFirestoreMapper`'s matching read/write lines) is safe immediately.
  Do this as a normal, focused, tested code change — no Firestore write is
  needed for the removal itself.
- **Any match:** do not remove the Dart fields yet. Either (a) explicitly,
  intentionally migrate/clear those specific fields in a one-time, backed
  up, authorized script (mirroring `scripts/migrate_ar_catalogue/`'s own
  backup + dry-run + `--apply` discipline) before removing the Dart fields,
  or (b) leave the fields exactly as they are today (inert, read-only-
  preserve) indefinitely — both are safe outcomes; only removing the Dart
  fields *without* first checking is not.
