# TWin AR — E-Commerce App with Augmented Reality

A production-grade Android e-commerce application built with Flutter and Firebase,
featuring an **in-room Augmented Reality product preview**, a real Stripe checkout,
and a full admin management panel.

> Final Year Project (FYP-2). The AR subsystem lets a customer place a
> true-to-scale 3D model of a furniture product into their own room, from a
> phone that is **not** ARCore-certified, using a three-tier device-adaptive
> rendering architecture.

---

## Contents

- [Overview](#overview)
- [Features](#features)
- [Room AR — Three-Tier Architecture](#room-ar--three-tier-architecture)
- [Tech Stack](#tech-stack)
- [Architecture & Patterns](#architecture--patterns)
- [Project Structure](#project-structure)
- [Getting Started](#getting-started)
- [Testing](#testing)
- [Security Model](#security-model)
- [Project Status](#project-status)
- [Screenshots](#screenshots)
- [Author](#author)

---

## Overview

TWin AR is a complete storefront + back office:

- **Customers** browse a Firestore-backed catalogue, filter and search, manage a
  cart, favourites and delivery addresses, check out with real (test-mode)
  Stripe payments, and track their orders — and, for supported products, preview
  them in AR before buying.
- **Super-admins** manage products, categories, inventory stock, orders &
  payments, and upload / validate / version / enable-disable / delete the 3D
  models that power the AR experience — all from an in-app admin panel gated by
  Firebase custom claims.
- The backend is **real Firebase** (Auth, Firestore, Storage, Cloud Functions)
  on a live project, with Cloud Functions as the exclusive trusted creator of
  orders and payments and a transactional stock-reservation model.

---

## Features

### Customer app
- Email/password auth with reactive session persistence and password reset
- Home (curated rails), Explore (search + category/price/attribute filters)
- Product Details with image gallery, variants, specifications, reviews
- Cart with per-line stock gating and quantity caps; Firestore-persisted per user
- Checkout with a real Stripe **test-mode** PaymentSheet (PKR), server-side
  order/payment creation and stock reservation
- Orders list + Order Detail with a live status timeline
- Profile, delivery address book (single authoritative default), favourites —
  all cross-device synced
- **"View in Your Room"** AR preview for AR-enabled products

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
  and orphan-object cleanup

### Backend (Firebase)
- Custom-claim (`superAdmin`) role authorization — never email-based
- Hardened `firestore.rules` + `storage.rules` with full emulator test suites
- Cloud Functions (Node 22, 2nd-gen): `createPaymentIntent` (auth + authoritative
  pricing + **atomic stock reservation before any charge**), `stripeWebhook`
  (signature-verified, idempotent, creates orders/payments from session
  snapshots), `releaseExpiredReservations` (scheduled 5-minute sweep)
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

## Tech Stack

- **Flutter** (Dart SDK `^3.12.2`; developed on Flutter 3.44 / Dart 3.12), **Provider** for state
- **Firebase**: Auth, Cloud Firestore, Storage, Cloud Functions (Node 22 / TypeScript)
- **Stripe** `flutter_stripe` (test mode only — no live account)
- **Native Android (Kotlin)** for AR: CameraX, OpenCV 4.12 (ArUco + `solvePnP`),
  Google Filament (glTF rendering), platform channels
- `file_picker`, `image_picker`, `permission_handler`, `printing` / `pdf`,
  `path_provider`, `crypto`, `shared_preferences`
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
  `CategoryRepository`, …) each with a real Firebase implementation and an
  in-memory test double
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
    services/              StorageService (+ Firebase/Mock), theme, utils, widgets
  features/
    home/  explore/  product_details/  cart/  checkout/  orders/
    favorites/  address/  profile/  auth/  onboarding/  splash/  legal/
    admin/
      dashboard/  product_management/  inventory/  orders_payments/
      ar_media_management/       Admin GLB upload / validate / preview / manage
    room_ar/
      capability/              Native probe + decideRoomArTier (tier routing)
      marker_ar/               Tier-2 engine (MVVM + native channel)
      preview/                 Tier-3 orbit renderer (MVVM + native channel)
      model_delivery/          Storage fetch + GLB inspector + cache + LKG
      views/ viewmodels/       Room-AR preparation screen
    virtual_try_on/            Prep/setup UI (rendering is a later phase)

android/app/src/main/kotlin/com/tahafayyaz/twin_ar/roomar/
                             Native AR: CameraX + OpenCV + Filament renderers
functions/                   Cloud Functions (Stripe, orders/payments, stock)
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

Current status: `flutter test` **949 passing**, Storage rules **57/57**,
Firestore rules **236/236**, Cloud Functions **89/89** unit + **63/63** emulator;
`flutter analyze` clean; `dart format` clean; `flutter build apk` (debug,
release/R8, split-per-abi) all green.

---

## Security Model

- **Roles** are Firebase **custom claims** (`superAdmin`) — email-based admin
  detection is never used.
- `firestore.rules` / `storage.rules` are hardened and covered by full emulator
  test suites; every block is field-shape / type / size validated where it
  matters.
- **Orders and payments** are `create: if false` for every client — created
  **exclusively** by Cloud Functions via the Admin SDK.
- **Stock** is reserved in an **atomic Firestore transaction before any Stripe
  PaymentIntent exists**; the webhook restores it exactly once on failure, and a
  scheduled sweep releases abandoned reservations.
- Stripe is **test mode only** — the secret key lives in Firebase Secret Manager
  (never in the repo); only the publishable `pk_test_` key reaches the client,
  via `--dart-define` (git-ignored).
- AR model objects require signed-in reads (approved products only for
  customers), super-admin writes, `.glb` shape, content-type and size gates, and
  provenance metadata (SHA-256 + version).

---

## Project Status

**Delivered**
- Full customer storefront + Firestore backend
- Admin panel (products, categories, inventory, orders & payments, AR & Media)
- Real Stripe test-mode checkout with server-side order/payment creation and
  atomic stock reservation
- Firebase Auth with custom-claim roles; hardened security rules
- **Room AR** — three-tier device-adaptive architecture; marker-based AR and the
  interactive 3D preview implemented and validated on-device for the flagship
  product set; secure Firebase Storage model delivery with integrity
  verification; admin model-management workflow
- **Virtual Try-On** — camera-based clothing try-on for supported products:
  Admin garment-asset pipeline, a secure server-side Cloud Function
  (Gemini image generation), and a customer capture → upload → generate →
  result flow, validated on-device across a curated clothing catalogue

**Future Work**
- Broaden the validated AR model catalogue to further products
- ARCore markerless (Tier 1) runtime, alongside a certified test device
- Wider cross-device validation matrix
- Google Sign-In; iOS support

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
