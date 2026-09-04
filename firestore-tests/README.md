# Firestore Security Rules tests

Full-fidelity verification of `firestore.rules` against the real Firestore
emulator (via `@firebase/rules-unit-testing`) — a separate Node toolchain
from `flutter test`, per the Lean Testing Policy in
`13_TESTING_AND_QA_RULES.md`. Not part of the Flutter app or its build.

`fake_cloud_firestore` (used inside `flutter test`) cannot evaluate
`request.resource.data`/`resource.data` or custom rule functions, so it
cannot verify the role-immutability and create-time field checks that are
the actual security boundary here. This directory exists specifically to
cover that gap with the real rules engine.

## Requirements

- Node.js (already required by `firebase-tools`)
- A JDK, version 21 or newer (required by the Firestore emulator itself,
  not by this project's Flutter/Dart code)

## Running

```bash
cd firestore-tests
npm install
npm test
```

This starts the Firestore emulator (`firebase emulators:exec`), loads the
real `../firestore.rules`, runs every case in `run_rules_tests.mjs`, prints
a PASS/FAIL line per case, and exits non-zero if anything failed.

## What it covers

**Phase 8.4 — `users/{uid}`:**

- A signed-in user can create only their own `users/{uid}` document, and
  only with `role: 'customer'` — never `'superAdmin'`.
- `uid`/`email` on a newly created document must match the caller's own
  authenticated identity.
- Owner read/update; a `superAdmin` custom claim can read any profile; no
  other signed-in user can read or write someone else's profile.
- `role`, `uid`, `email`, and `createdAt` can never be changed via update,
  even by the owner.
- A create with any field outside the six known profile fields
  (`uid`/`email`/`displayName`/`phone`/`role`/`createdAt`) is denied.
- An update that touches any field other than `displayName`/`phone`/
  `avatarStoragePath` (Phase 8.7) - adding a brand-new field or changing an
  existing unlisted one - is denied, even by the owner.
- Delete is always denied.

**Phase 8.7 — `users/{uid}.avatarStoragePath`:**

- The owner can set `avatarStoragePath` to a path under their own
  `users/{uid}/profile/` prefix, clear it back to `null`, or update it
  alongside `displayName`/`phone` in the same write.
- The owner CANNOT set `avatarStoragePath` to a path under a different
  user's uid, or to an arbitrary string outside the
  `users/{uid}/profile/` prefix (e.g. a raw URL) - the core guard that
  prevents a customer from ever pointing their own profile at someone
  else's avatar object.
- A non-owner cannot set another user's `avatarStoragePath`.
- Setting `avatarStoragePath` cannot be combined with a `role` change in
  the same write to smuggle a privilege escalation through.

**Phase 8.5 — `products/{id}` reads:**

- A signed-in customer can read a `published && isActive` product.
- A signed-in customer cannot read a draft product, or an inactive one.
- An unauthenticated client cannot read any product.
- A `superAdmin` custom claim can read a draft product and an inactive
  product (Admin sees everything, regardless of status).

**Phase 8.6 — `products/{id}` writes:**

- A `superAdmin` custom claim can create, update, and delete a product.
- A signed-in customer cannot create, update, or delete a product.
- An unauthenticated client cannot write a product.
- The developer-only seed script (`scripts/seed_products/`) uses the Admin
  SDK, which bypasses this rule entirely regardless.

**Phase 8.8 — `categories/{categoryId}`:**

- A `superAdmin` custom claim can create a category with the full valid
  field set (`name`/`key`/`kind`/`imageUrl`/`isActive`/`sortOrder`),
  including one whose `imageUrl` is a real Storage download URL.
- Create is denied when `key != categoryId`, when `key` isn't the canonical
  slug shape `slugifyCategoryName()` produces (lowercase alphanumeric
  segments separated by single hyphens - `---`/`-decor`/`decor-`/
  `home--decor` are all rejected), when `kind` is outside the closed
  five-value set (including the `all` UI-only sentinel, which must never be
  stored), when `name` is empty, whitespace-only, has leading/trailing
  whitespace, or is over 60 characters (internal whitespace, e.g. "Outdoor
  Furniture", remains valid), when `sortOrder` is negative or a fractional
  number (must be an integer), when `isActive` isn't a boolean, when an
  unexpected extra field is present, or when a required field is missing.
- A signed-in customer or an unauthenticated client cannot create a
  category.
- A signed-in customer can read an active category but not an inactive one;
  an unauthenticated client cannot read any category; a `superAdmin` can
  read both active and inactive categories.
- A `superAdmin` can update `name`/`imageUrl`/`isActive`/`sortOrder`, but
  CANNOT change `key` or `kind` on update - both are permanently immutable
  after creation (`kind` deliberately so, to prevent a future denormalized
  `categoryKind` field from silently drifting out of sync - see
  `firestore.rules`' Phase 8.8 header comment). The updated `name` is
  validated with the same rules as create (length, non-whitespace-only) and
  `sortOrder` must stay a non-negative integer. A signed-in customer cannot
  update a category at all.
- A `superAdmin` can delete a non-seeded (custom) category, but CANNOT
  delete any of the five permanently protected seeded category IDs
  (`furniture`/`clothing`/`rugs`/`decor`/`lighting`) - this is a structural
  protection, not just a client-side convenience. A signed-in customer
  cannot delete any category.

**All phases:** every other collection is denied by the catch-all rule
(nothing beyond what's explicitly implemented is left open).

Re-run this whenever `firestore.rules` changes, and extend it with new
cases as later phases (8.8 onward) add rules for other collections.
