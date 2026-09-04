# Firebase Storage Security Rules tests

Full-fidelity verification of `../storage.rules` against the real Storage
emulator (via `@firebase/rules-unit-testing`) — a separate Node toolchain
from `flutter test`, per the Lean Testing Policy in
`13_TESTING_AND_QA_RULES.md`. Not part of the Flutter app or its build.
Mirrors `../firestore-tests/` exactly.

## Requirements

- Node.js (already required by `firebase-tools`)
- A JDK, version 21 or newer (required by the Storage emulator itself, not
  by this project's Flutter/Dart code) — the same requirement
  `../firestore-tests/README.md` already documents for the Firestore
  emulator.

## Running

```bash
cd storage-tests
npm install
npm test
```

This starts the Storage emulator (`firebase emulators:exec`), loads the
real `../storage.rules`, runs every case in `run_rules_tests.mjs`, prints a
PASS/FAIL line per case, and exits non-zero if anything failed.

## What it covers

**`products/{productId}/images/{imageId}` (public read, `superAdmin`-only
write):**

- An unauthenticated client and a signed-in customer can both read a
  product image (public read).
- A `superAdmin` custom claim can create, update (overwrite), and delete a
  product image.
- A signed-in customer and an unauthenticated client cannot create, update,
  or delete a product image.
- A `superAdmin` upload is rejected for a non-image content type
  (`application/pdf`) and rejected over the 10 MB product-image limit.

**`users/{uid}/profile/{imageId}` (owner read/write, admin read-only, no
one else):**

- The owner can create, update (replace), and delete their own avatar.
- A different signed-in user cannot write to another user's avatar path —
  the core write-isolation guarantee.
- An unauthenticated client cannot write any avatar.
- A `superAdmin` can **read** any customer's avatar but **cannot write** to
  one — admin access is read-only here, unlike the full read/write access
  `isAdmin()` gets on `products/**`.
- The owner can read their own avatar.
- A different signed-in user **cannot** read another user's avatar — the
  core read-isolation guarantee (User 2 must never see User 1's avatar).
  This is the case that most directly protects the requirement that avatars
  are never exposed cross-user.
- An unauthenticated client cannot read any avatar (avatars are NOT public,
  unlike product images).
- Avatar upload is rejected for a non-image content type and rejected over
  the 2 MB avatar limit.

**`categories/{categoryId}/images/{imageId}` (Phase 8.8 — public read,
`superAdmin`-only write, mirrors product images with a smaller size cap):**

- An unauthenticated client and a signed-in customer can both read a
  category image (public read).
- A `superAdmin` custom claim can create, update (overwrite/replace), and
  delete a category image.
- A signed-in customer and an unauthenticated client cannot create, update,
  or delete a category image.
- A `superAdmin` upload is rejected for a non-image content type and
  rejected over the 5 MB category-image limit (smaller than the 10 MB
  product-image ceiling — a category image is a single thumbnail, never a
  gallery).
- Does not change `products/{productId}/images/{imageId}` or
  `users/{uid}/profile/{imageId}` behavior in any way — both trees above are
  untouched by Phase 8.8.

**Catch-all:** every path outside the three trees above is denied to
everyone, including a `superAdmin`.

Re-run this whenever `storage.rules` changes, and extend it with new cases
if a later phase adds another Storage tree (e.g. AR/VTO assets, which stay
mock/local paths through Phase 8.7/8.8 and are explicitly out of scope
here).
