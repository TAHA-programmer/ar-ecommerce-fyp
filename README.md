# TWin AR — E-Commerce App with Augmented Reality

A production-grade Android e-commerce application built with Flutter and Firebase,
featuring an **in-room Augmented Reality product preview**, **camera-based Virtual
Try-On for clothing**, a real Stripe checkout, a Ratings & Reviews system, and a
full admin management panel.

> Final Year Project (FYP-2). The AR subsystem lets a customer place a
> true-to-scale 3D model of a furniture product into their own room, from a
> phone that is **not** ARCore-certified, using a three-tier device-adaptive
> rendering architecture.

---

## Contents

- [Overview](#overview)
- [Features](#features)
- [Room AR — Three-Tier Architecture](#room-ar--three-tier-architecture)
- [Virtual Try-On](#virtual-try-on)
- [Tech Stack](#tech-stack)
- [Architecture & Patterns](#architecture--patterns)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Testing](#testing)
- [Security Model](#security-model)
- [Project Status](#project-status)
- [Known Limitations](#known-limitations)
- [Support](#support)
- [Screenshots](#screenshots)
- [Author](#author)

---

## Overview

TWin AR is a complete storefront + back office:

- **Customers** browse a Firestore-backed catalogue, filter and search, manage a
  cart, favourites and delivery addresses, check out with real (test-mode)
  Stripe payments, track their orders, and rate/review products they've
  received — and, for supported products, preview them in AR or try clothing on
  virtually before buying.
- **Super-admins** manage products, categories, inventory stock, orders &
  payments, customer reviews, and upload / validate / version / enable-disable /
  delete the 3D models and garment assets that power the AR and Virtual Try-On
  experiences — all from an in-app admin panel gated by Firebase custom claims.
- The backend is **real Firebase** (Auth, Firestore, Storage, Cloud Functions)
  on a live project, with Cloud Functions as the exclusive trusted creator of
  orders, payments, and reviews, and a transactional stock-reservation model.

---

## Features

### Customer app
- Email/password authentication **and Google Sign-In**, with reactive session
  persistence and password reset
- Home (curated rails driven by real signals — Best Sellers by units sold,
  Popular by favourite count, Featured, Recently Viewed), Explore (search +
  category/price/attribute filters)
- Product Details with image gallery, variants, specifications, and live
  ratings/reviews
- Cart with per-line stock gating and quantity caps; Firestore-persisted per user
- Checkout with a real Stripe **test-mode** PaymentSheet (PKR), server-side
  order/payment creation and stock reservation
- Orders list + Order Detail with a live status timeline
- **Ratings & Reviews** — rate and review a product after it's delivered, edit
  within a grace window, see other customers' reviews (author names are
  masked, e.g. "Ayesha K." — never an email or phone number), and report a
  review you believe is spam, offensive, or fake
- **"View in Your Room"** AR preview for AR-enabled products
- **Virtual Try-On** for supported clothing — capture or choose a photo,
  generate a preview, and manage/delete your own Try-On data at any time
- Profile, delivery address book (single authoritative default), favourites,
  My Reviews — all cross-device synced
- Help & Support (FAQ covering ordering, AR, Try-On, reviews, payments) with a
  working **Contact Support** action that opens your email app addressed to
  the project's real support mailbox; Privacy Policy and Terms & Conditions
  kept in sync with what the app actually does and stores

### Admin panel
- Dashboard (products / orders / revenue / low-stock metrics)
- Product management (add / edit / draft / publish / delete) with a single
  reusable form; progressive disclosure by category
- Dynamic, Firestore-backed categories with real image upload and a
  protected-seed-category policy
- Inventory management (staged per-row stock edits, low-stock filter,
  server-stamped "last updated")
- Orders & Payments (Orders tab + Payments tab), Admin Order Detail with a
  status-mutation lifecycle
- **AR & Media management** — real `.glb` model upload with byte-level
  validation (magic bytes, structure, self-contained, bounding-box vs declared
  dimensions, floor-centred, SHA-256, size), dimension capture, an interactive
  3D preview, versioned replace-without-downtime, enable/disable the customer
  entry point, and an explicit confirmed delete workflow — with upload rollback
  and orphan-object cleanup; a matching garment-asset pipeline for Virtual
  Try-On
- **Reviews Moderation** — every review across every product, filterable by
  status/flagged, with a report audit trail and hide / restore / reject actions
- **Notifications** — a dedicated screen listing pending orders and low-stock
  products, with a live numeric badge on the bell (never a fake or hardcoded
  count, and never shown when there's nothing to flag)
- Account menu with a real, confirmed sign-out flow — no placeholder tiles, no
  "mock" labels

### Backend (Firebase)
- Custom-claim (`superAdmin`) role authorization — never email-based
- Hardened `firestore.rules` + `storage.rules` with full emulator test suites
- Cloud Functions (Node 22, 2nd-gen, `us-central1`):
  - **Checkout**: `createPaymentIntent` (auth + authoritative pricing +
    **atomic stock reservation before any charge**), `stripeWebhook`
    (signature-verified, idempotent, creates orders/payments from session
    snapshots), `releaseExpiredReservations` (scheduled 5-minute sweep)
  - **Ratings & Reviews**: `submitReview`, `deleteReview`, `reportReview`,
    `moderateReview`, `cleanupUserReviewsData`
  - **Virtual Try-On**: `generateTryOn` (Google Gemini image generation),
    `cleanupExpiredTryOnMedia`, `cleanupUserTryOnData`
  - **Home content signals**: `adjustFavoriteCount`, `adjustStatsOnOrderCancel`
    (maintain the `productStats/{id}` aggregate behind Best Sellers/Popular)
- Content-addressed image storage with same-save rollback

---

## Room AR — Three-Tier Architecture

The primary test device (Infinix Hot 40) is not ARCore-certified, so the app
probes the device at runtime and selects the best experience it can actually
run. The **same GLB per product** feeds all three tiers (authoring contract:
`+Y` up, front `−Z`, floor-centred, real metres).

| Tier | Name | Chosen when | How it works |
|---|---|---|---|
| **1** | ARCore markerless | Device is ARCore-certified | Google Play Services for AR — markerless plane detection, tap-to-place at true scale *(architecture in place; runtime scheduled for a later iteration with certified hardware)* |
| **2** | OpenCV Marker AR | Non-ARCore Android + camera + OpenGL ES 3.0 | CameraX feed + OpenCV ArUco marker (`DICT_5X5_100`, printed A4) + `solvePnP` pose + Google Filament rendering; One-Euro pose smoothing, marker-size calibration for absolute scale, tap-to-place, drag (clamped), rotate, "Face me", contact shadow, honest *Searching / Tracking / Holding / Too Far* states |
| **3** | Interactive 3D Preview | Camera AR unavailable (no camera / permission denied) | A no-camera transparent Filament **orbit** viewer — drag to rotate, two-finger pan, pinch zoom, double-tap reset; "actual size · W·D·H" caption |

**Secure model delivery.** Models are fetched from Firebase Storage **by object
path** (never a URL), downloaded to a private staging file with a hard size cap,
then verified — GLB magic bytes + declared length + chunk structure + **SHA-256**
+ a **scene-graph bounding-box match** against the declared dimensions (±3 %) +
floor-centred sanity — before an atomic promote into an on-disk cache keyed by
`path + version + sha`. On a failed refresh it serves a fully-revalidated
last-known-good file, else the byte-identical app-bundled model. The renderer is
never handed an unverified or partial file.

**Customer flow:** `Product Details → "View in Your Room" → preparation screen
(adapts to the resolved tier) → Start AR / View 3D Preview`.

---

## Virtual Try-On

For supported clothing products, a customer can preview how a garment might
look on them without a live camera feed:

1. Choose the male/female model type and give explicit, per-session consent.
2. Capture a photo with the camera, or pick one from the gallery.
3. The photo is uploaded and sent to **Google Gemini** (via the server-side
   `generateTryOn` Cloud Function) to generate a preview image — the source
   photo is deleted immediately after generation.
4. The generated preview is deleted when the customer closes it, deletes it
   themselves, or automatically within 24 hours, whichever comes first.

Every Try-On asset (garment references, generated previews) is managed through
an Admin garment pipeline mirroring the Room AR asset workflow, and a customer
can delete all of their own Try-On data at any time from **Profile → Delete My
Try-On Data**.

---

## Tech Stack

- **Flutter** (Dart SDK `^3.12.2`; developed on Flutter 3.44 / Dart 3.12), **Provider** for state
- **Firebase**: Auth (Email/Password + Google Sign-In), Cloud Firestore,
  Storage, Cloud Functions (Node 22 / TypeScript)
- **Stripe** `flutter_stripe` (test mode only — no live account)
- **Google Gemini** — server-side Virtual Try-On image generation
- **Native Android (Kotlin)** for AR: CameraX, OpenCV 4.12 (ArUco + `solvePnP`),
  Google Filament (glTF rendering), platform channels
- `google_sign_in`, `url_launcher`, `file_picker`, `image_picker`,
  `permission_handler`, `printing` / `pdf`, `path_provider`, `crypto`,
  `shared_preferences`
- Emulator-based rule testing (`@firebase/rules-unit-testing`), `vitest` for
  Cloud Functions

---

## Architecture & Patterns

- **Feature-first** directory layout under `lib/features/`
- **MVVM + Provider + Repository** — `View` (widgets) → `ViewModel`
  (`ChangeNotifier`, owns all state and decisions) → `Repository` / `Service`
  (data access). No Clean-Architecture use-case layer.
- A single shared `CommerceDatabase` abstraction (`FirestoreCommerceDatabase` in
  production, `MockCommerceDatabase` as the test double) backs both the customer
  and admin surfaces
- Narrow, purpose-fit service interfaces (`AuthRepository`, `StorageService`,
  `CategoryRepository`, `MailLauncherService`, …) each with a real
  implementation and an in-memory/fake test double
- Thin platform-channel boundaries for the native AR engine — all pose /
  placement / tier decisions live in Dart ViewModels; the native side only
  renders

---

## Project Structure

```
lib/
  app/                     App shell, routing, providers, AuthSessionState
  core/
    data/                  CommerceDatabase (+ Firestore/Mock), Firestore mappers
    models/                Product, order, category, auth, AR-metadata models
    services/              StorageService, MailLauncherService (+ real/mock), theme, utils, widgets
  features/
    home/  explore/  product_details/  cart/  checkout/  orders/
    favorites/  address/  profile/  auth/  onboarding/  splash/  legal/
    reviews/                   Ratings & Reviews — write/edit/delete, My Reviews,
                                product review sections, report flow
    recently_viewed/           Per-customer product-view history
    virtual_try_on/            Consent → capture → upload → generate → result
    admin/
      dashboard/  product_management/  inventory/  orders_payments/
      ar_media_management/       Admin GLB/garment upload / validate / preview / manage
      reviews_moderation/        Admin report queue + hide/restore/reject
      notifications/             Live pending-orders + low-stock notifications
    room_ar/
      capability/              Native probe + decideRoomArTier (tier routing)
      marker_ar/               Tier-2 engine (MVVM + native channel)
      preview/                 Tier-3 orbit renderer (MVVM + native channel)
      model_delivery/          Storage fetch + GLB inspector + cache + LKG
      views/ viewmodels/       Room-AR preparation screen

android/app/src/main/kotlin/com/tahafayyaz/twin_ar/roomar/
                             Native AR: CameraX + OpenCV + Filament renderers
functions/                   Cloud Functions (Stripe, reviews, Try-On, home stats)
firestore.rules  storage.rules  firestore.indexes.json
firestore-tests/  storage-tests/   Emulator rule-test suites
scripts/                     Node helpers: seeding, catalogue migrations, GLB upload
test/                        Flutter unit + widget tests
```

---

## Getting Started

### Prerequisites
- Flutter SDK (Dart `>= 3.12.2`) and the Android toolchain
- A Firebase project — **or** use the committed config, which targets the
  project used during development (`android/app/google-services.json`,
  `lib/firebase_options.dart`). To point at your own project, run
  `flutterfire configure` and replace those files.
- Node 22 (only if you want to run/deploy the Cloud Functions or the emulator
  rule tests)

### Run
```bash
flutter pub get

# Create your Stripe test-mode config (git-ignored):
cp dart_defines.example.json dart_defines.json
#   then edit dart_defines.json and set your own pk_test_... key

flutter run --dart-define-from-file=dart_defines.json
```

> **Every build** — debug, release, or an AAB — must pass
> `--dart-define-from-file=dart_defines.json`, or Checkout silently shows
> "Card payment is temporarily unavailable" regardless of backend health.

### Build
```bash
flutter build apk --release --dart-define-from-file=dart_defines.json
flutter build apk --release --split-per-abi --dart-define-from-file=dart_defines.json
```

The app is **Android-only** (`com.tahafayyaz.twin_ar`); the `ios/` folder is the
unused default Flutter scaffold.

---

## Testing

```bash
flutter test                                   # Flutter unit + widget tests

# Emulator rule tests (require the Firebase CLI):
cd storage-tests   && npm ci && npm test        # Storage security rules
cd firestore-tests && npm ci && npm test        # Firestore security rules
cd functions       && npm ci && npm test        # Cloud Functions (unit)
cd functions       && npm run test:emulator     # Cloud Functions (emulator)
```

Current status: `flutter test` **1624 passing**, Firestore rules **293/293**,
Storage rules **111/111**, Cloud Functions **251/251** unit + **217/217**
emulator; `flutter analyze` clean; `dart format` clean; `flutter build apk`
(debug, release/R8, split-per-abi) all green.

---

## Security Model

- **Roles** are Firebase **custom claims** (`superAdmin`) — email-based admin
  detection is never used.
- `firestore.rules` / `storage.rules` are hardened and covered by full emulator
  test suites; every block is field-shape / type / size validated where it
  matters.
- **Orders, payments, and reviews** are `create: if false` for every direct
  client write — created **exclusively** by Cloud Functions via the Admin SDK,
  which independently verify eligibility (e.g. a review requires a genuinely
  delivered order for that product) before writing anything.
- **Stock** is reserved in an **atomic Firestore transaction before any Stripe
  PaymentIntent exists**; the webhook restores it exactly once on failure, and a
  scheduled sweep releases abandoned reservations.
- Stripe is **test mode only** — the secret key lives in Firebase Secret Manager
  (never in the repo); only the publishable `pk_test_` key reaches the client,
  via `--dart-define` (git-ignored).
- A published review never exposes the reviewer's email, phone, or account
  details — only a masked display name computed server-side.
- AR model / garment objects require signed-in reads (approved products only
  for customers), super-admin writes, strict content-type and size gates, and
  provenance metadata (SHA-256 + version).

---

## Project Status

**Delivered**
- Full customer storefront + Firestore backend
- Admin panel (products, categories, inventory, orders & payments, AR & Media,
  reviews moderation, live notifications)
- Real Stripe test-mode checkout with server-side order/payment creation and
  atomic stock reservation
- Firebase Auth (Email/Password + **Google Sign-In**) with custom-claim roles;
  hardened security rules
- **Room AR** — three-tier device-adaptive architecture; marker-based AR and the
  interactive 3D preview implemented and validated on-device for the flagship
  product set; secure Firebase Storage model delivery with integrity
  verification; admin model-management workflow
- **Virtual Try-On** — camera-based clothing try-on for supported products:
  Admin garment-asset pipeline, a secure server-side Cloud Function
  (Gemini image generation), and a customer capture → upload → generate →
  result flow, validated on-device across a curated clothing catalogue
- **Ratings & Reviews** — post-delivery rating/review with an edit window,
  masked public author names, customer reporting, and full Admin moderation
  (report queue, hide/restore/reject), deployed live
- **Dynamic Home content** — Best Sellers, Popular, Featured, and Recently
  Viewed all driven by real Firestore signals instead of static/mock data
- Functional Contact Support (opens a prepared email to a real, monitored
  mailbox), and Profile legal/help content kept accurate against actual app
  behaviour

**Future Work**
- Broaden the validated AR model catalogue to further products
- ARCore markerless (Tier 1) runtime, alongside a certified test device
- Wider cross-device validation matrix
- Google Play App Signing / Play-distributed AAB fingerprint registration
- iOS support

---

## Known Limitations

Documented and deliberately deferred — not silently dropped:

- **Order cancellation does not restore stock.** Cancelling a paid/reserved
  order does not increment `stockQuantity` back; the correct fix is a
  transactional Cloud Function change. Operational workaround: manually
  restore the cancelled quantity via Admin Inventory.
- **A long-open Admin Edit Product form can overwrite a newer concurrent stock
  edit** on save, since the form resends its originally-loaded stock value
  verbatim. Operational workaround: keep Admin Edit Product sessions short;
  use the dedicated Inventory screen for stock-only edits.
- **Rating-sorted product lists** consider at most the 500 most relevant
  published reviews per product (a bounded in-memory re-sort, not an indexed
  query) — generous at current volume.
- A review report filed against an account that is later deleted is not
  purged (harmless, admin-only readable).

---

## Support

Found an issue or have a question about the app? Contact
**twinar.support@gmail.com**, or use **Profile → Help & Support → Contact
Support** in the app itself, which opens a prepared email to the same address.

---

## Screenshots

_Add screenshots here (`docs/screenshots/…`)._

| Home | Explore | Product Details | Room AR |
|---|---|---|---|
| | | | |

| Admin Dashboard | Product Form | AR & Media | 3D Preview |
|---|---|---|---|
| | | | |

---

## Author

**Taha Fayyaz** — Final Year Project (FYP-2).

Built with Flutter, Firebase, OpenCV and Google Filament.

_© 2026 Taha Fayyaz. All rights reserved. This repository is published for
academic review; add an explicit open-source `LICENSE` file if you wish to
license it for reuse._
