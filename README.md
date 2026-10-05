# TWin AR — E-Commerce with Augmented Reality

![Platform](https://img.shields.io/badge/platform-Android-3DDC84?logo=android&logoColor=white)
![Flutter](https://img.shields.io/badge/Flutter-3.44-02569B?logo=flutter&logoColor=white)
![Firebase](https://img.shields.io/badge/backend-Firebase-FFCA28?logo=firebase&logoColor=black)
![Stripe](https://img.shields.io/badge/payments-Stripe%20test%20mode-635BFF?logo=stripe&logoColor=white)

**TWin AR** is a full-stack Android shopping app built with Flutter and Firebase.
Customers browse a live catalogue, check out with Stripe (test mode), and — for
supported products — **place true-to-scale furniture in their own room with
Augmented Reality** or **try clothing on virtually** before buying. A built-in
admin panel manages the catalogue, orders, reviews and the 3D / garment assets
that power the AR and Try-On experiences.

> Final Year Project (FYP-2). The AR subsystem works on phones that are **not**
> ARCore-certified, using a three-tier, device-adaptive rendering design.

---

## Download

**Latest release:** [github.com/TAHA-programmer/ar-ecommerce-fyp/releases/latest](https://github.com/TAHA-programmer/ar-ecommerce-fyp/releases/latest)

| File | For | Download size | SHA-256 |
|---|---|---|---|
| [`twin-ar-v1.0.0-arm64-v8a.apk`](https://github.com/TAHA-programmer/ar-ecommerce-fyp/releases/download/v1.0.0/twin-ar-v1.0.0-arm64-v8a.apk) | 64-bit ARM Android phones | ≈ 62.9 MB | `50de5d3f6854dd0cd6c84bec46aa21614db625190961e4dca281ddc408fce20a` |

**Requirements:** Android 7.0+ (API 24), a 64-bit ARM (arm64-v8a) device. Room AR needs a working camera; Virtual Try-On accepts a photo selected from your gallery (no rear camera required). The download is about 62.9 MB; the installed app was observed at about 136 MB, so keep additional free space for installation and cache.

> **Test build.** Checkout uses **Stripe test mode only** (no real payments — use Stripe's published test cards) and the app talks to the project's **live Firebase backend**; accounts you create are real accounts in that project.

**Install:** download the APK on your phone → allow *Install unknown apps* for your browser or Files app → open the file → *Install*. Play Protect may warn about an unrecognized developer; that is expected for apps installed outside the Play Store.

**Verify (PowerShell):**

```powershell
Get-FileHash .\twin-ar-v1.0.0-arm64-v8a.apk -Algorithm SHA256
```

The result must match the SHA-256 in the table. The APK is signed with the project's release key (certificate SHA-256 `30:49:23:80:…:55:C4:3C`). To build it yourself, see [Building release APKs and AABs](#building-release-apks-and-aabs).

---

## Contents

- [Download](#download)
- [What it does](#what-it-does)
- [Features](#features)
- [Room AR — three-tier architecture](#room-ar--three-tier-architecture)
- [Virtual Try-On](#virtual-try-on)
- [Push notifications (FCM)](#push-notifications-fcm)
- [Tech stack](#tech-stack)
- [Architecture and project structure](#architecture-and-project-structure)
- [Getting started](#getting-started)
- [Backend setup and deployment](#backend-setup-and-deployment)
- [Testing](#testing)
- [Building release APKs and AABs](#building-release-apks-and-aabs)
- [Security model](#security-model)
- [Project status](#project-status)
- [Support](#support)
- [Author](#author)

---

## What it does

| Role | What they can do |
|---|---|
| **Customer** | Browse, search and filter products · manage cart, favourites and addresses · pay with Stripe (**test mode**) · track orders · rate and review delivered products · preview furniture in AR · try clothing on virtually · receive order and moderation notifications |
| **Super-admin** | Manage products, categories, stock, orders and payments · moderate reviews · upload, validate, version and enable/disable 3D models and garment assets · see live pending-order and low-stock alerts |
| **Backend** | Real Firebase (Auth, Firestore, Storage, Cloud Functions, Cloud Messaging). Cloud Functions are the only trusted creators of orders, payments and reviews, and stock is reserved transactionally before any charge. |

The app is **Android-only** (`com.tahafayyaz.twin_ar`, min SDK 24); the `ios/`
folder is the unused default Flutter scaffold. Payments run against Stripe
**test mode only** — there is no live-money checkout.

---

## Features

### Customer app

| Area | Highlights |
|---|---|
| **Sign-in** | Email/password and **Google Sign-In**, session persistence, password reset, confirmed logout with a blocking "Signing out…" state |
| **Discovery** | Home rails driven by real signals (Best Sellers by units sold, Popular by favourites, Featured, Recently Viewed) · Explore with search and category / price / attribute filters |
| **Product details** | Image gallery, variants, specifications, live ratings and reviews |
| **Cart and checkout** | Per-user Firestore cart with stock gating and quantity caps · Stripe PaymentSheet (PKR, test mode) · server-side order and payment creation |
| **Orders** | Order list and detail with a live status timeline |
| **Ratings and reviews** | Review a product after delivery, edit within a 30-day window, masked public author names (e.g. "Ayesha K."), report spam or abuse |
| **Room AR** | "View in Your Room" for AR-enabled products — see [below](#room-ar--three-tier-architecture) |
| **Virtual Try-On** | Photo-based clothing preview — see [below](#virtual-try-on) |
| **Notifications** | In-app Notification Centre with unread badge and per-category push switches — see [below](#push-notifications-fcm) |
| **Account** | Profile, address book (single default), favourites, My Reviews, Help & Support with a working **Contact Support** email action, Privacy Policy and Terms |

### Admin panel

| Area | Highlights |
|---|---|
| **Dashboard** | Product, order, revenue and low-stock metrics |
| **Products and categories** | Add / edit / draft / publish / delete with one reusable form · Firestore-backed categories with image upload and protected seed categories |
| **Inventory** | Staged per-row stock edits, low-stock filter, server-stamped "last updated" |
| **Orders and payments** | Orders and Payments tabs, order detail with a status lifecycle |
| **AR and media** | Real `.glb` upload with byte-level validation (magic bytes, structure, bounding box vs declared size, floor-centred, SHA-256, size cap), interactive 3D preview, versioned replace, enable/disable the customer entry point, confirmed delete with rollback and orphan cleanup; matching garment-asset pipeline for Try-On |
| **Reviews moderation** | Every review across products, filter by status or flagged, report audit trail, hide / restore / reject |
| **Notifications** | Live list of pending orders and low-stock products with a numeric bell badge (state-derived, never hard-coded), plus push alerts that deep-link into the right screen |
| **Account** | Confirmed sign-out |

### Backend (Firebase)

- Roles are Firebase **custom claims** (`superAdmin`); email is never used to grant admin.
- Hardened `firestore.rules` and `storage.rules`, each with an emulator test suite.
- **21 Cloud Functions** (Node 22, `us-central1`):

| Group | Functions |
|---|---|
| Checkout | `createPaymentIntent` (auth + authoritative pricing + atomic stock reservation before any charge), `stripeWebhook` (signature-verified, idempotent), `releaseExpiredReservations` (5-minute sweep) |
| Ratings and reviews | `submitReview`, `deleteReview`, `reportReview`, `moderateReview`, `cleanupUserReviewsData` |
| Virtual Try-On | `generateTryOn` (Google Gemini), `cleanupExpiredTryOnMedia`, `cleanupUserTryOnData` |
| Home signals | `adjustFavoriteCount`, `adjustStatsOnOrderCancel` (maintain the `productStats` aggregate) |
| Notifications | `registerDevice`, `unregisterDevice`, `onOrderCreatedNotify`, `onOrderStatusNotify`, `onProductStockNotify`, `onReviewNotify`, `onStripeEventNotify`, `cleanupUserNotificationData` — behind a `NOTIFICATIONS_ENABLED` kill-switch |

---

## Room AR — three-tier architecture

The app probes the device at runtime and picks the best experience it can
actually run. The **same GLB per product** feeds all three tiers (authoring
contract: `+Y` up, front `−Z`, floor-centred, real metres).

| Tier | Name | Used when | How it works |
|---|---|---|---|
| **1** | ARCore markerless | Device is ARCore-certified | Google Play Services for AR: plane detection, tap-to-place at true scale, drag / rotate / reset. Validated on a physical ARCore-capable device. |
| **2** | OpenCV marker AR | No ARCore, but camera + OpenGL ES 3.0 | CameraX feed, OpenCV ArUco marker (`DICT_5X5_100`, printed A4 sheet), `solvePnP` pose, Google Filament rendering, One-Euro smoothing, marker-size calibration for absolute scale, tap-to-place, clamped drag, rotate, contact shadow, honest *Searching / Tracking / Holding / Too Far* states |
| **3** | Interactive 3D preview | Camera AR unavailable (no camera or permission denied) | Camera-less Filament orbit viewer: drag to rotate, two-finger pan, pinch zoom, double-tap reset, "actual size · W·D·H" caption |

**Customer flow:** Product Details → **View in Your Room** → preparation screen
(adapts to the detected tier) → Start AR / View 3D Preview. Only products with a
valid, approved model show the entry point.

**Secure model delivery.** Models are fetched from Firebase Storage **by object
path** (never a URL), downloaded to a staging file with a hard size cap, then
verified — GLB magic bytes, declared length, chunk structure, **SHA-256**, a
scene-graph bounding-box match against the declared dimensions (±3 %) and a
floor-centred check — before an atomic promote into an on-disk cache keyed by
`path + version + sha`. If a refresh fails it serves a re-validated last-known-good
file, else the byte-identical bundled model, so AR still works offline. The
renderer is never handed an unverified file.

---

## Virtual Try-On

For supported clothing, a customer can preview a garment on themselves:

1. Choose the model type and give explicit, per-session consent.
2. Capture a photo or pick one from the gallery.
3. The photo is uploaded and sent to **Google Gemini** through the server-side
   `generateTryOn` Cloud Function; the source photo is deleted right after
   generation.
4. The generated preview is deleted when the customer closes or deletes it, or
   automatically within 24 hours.

Garment references are managed through an admin pipeline that mirrors the Room
AR asset workflow, and customers can erase all of their Try-On data at any time
from **Profile → Delete My Try-On Data**.

---

## Push notifications (FCM)

Server-driven push over **Firebase Cloud Messaging**. A push is only a
convenience: the in-app Notification Centre, My Orders and the admin screens are
always the source of truth, and delivery is **best-effort** (Doze, battery savers,
a force-stopped app or no network can delay or drop it).

| Audience | Push events |
|---|---|
| Customer | Order confirmed / shipped / delivered / cancelled · payment refunded because a reservation was lost · review hidden or not published by moderation |
| Customer (inbox only) | Order placed · review restored |
| Admin | New paid order · low stock (1–5) and out of stock · review flagged by repeated reports · payment issue |

- **Notification Centre** — newest first, grouped by day, loading / empty / error
  states, works offline from the Firestore cache; unread badge on the Home and
  Explore bell.
- **Preferences** — customers can switch off *Order updates* and *Reviews &
  moderation* pushes (the inbox still records them); admins have four switches.
- **Permission** (Android 13+) is requested at a relevant moment — after the first
  order, from Settings, or via a one-time admin explainer — never at launch.
- **Foreground / background / terminated** — an in-app tappable banner while open;
  otherwise the OS renders it on one of four Android channels.
- **Safe deep links** — payloads are strictly validated and mapped to hard-coded
  screens (never a route or URL); a notification for another account, or an admin
  screen for a non-admin, is dropped.
- **Device registration** — the server stamps the role from the verified ID-token
  claim; tokens live in a server-only collection keyed by SHA-256, capped at 10
  per user, and are removed on logout and on account deletion (plus failed-send
  pruning and a 60-day TTL).
- Customer notices never contain an address, items or amounts.

---

## Tech stack

| Layer | Technology |
|---|---|
| App | **Flutter** (Dart `^3.12.2`, developed on Flutter 3.44) · **Provider** state management |
| Firebase | Auth (Email/Password + Google Sign-In) · Cloud Firestore · Storage · Cloud Functions (Node 22, TypeScript) · Cloud Messaging |
| Payments | Stripe via `flutter_stripe` (**test mode only**) |
| AI | Google Gemini (server-side, Virtual Try-On image generation) |
| Native Android (Kotlin) | CameraX · OpenCV 4.12 (ArUco, `solvePnP`) · Google Filament (glTF) · ARCore · platform channels |
| Other packages | `google_sign_in`, `firebase_messaging`, `permission_handler`, `file_picker`, `image_picker`, `url_launcher`, `printing` / `pdf`, `path_provider`, `crypto`, `shared_preferences` |
| Testing | `flutter_test`, `@firebase/rules-unit-testing`, `vitest` |

---

## Architecture and project structure

- **Feature-first** layout under `lib/features/`.
- **MVVM + Provider + Repository** — View (widgets) → ViewModel (`ChangeNotifier`,
  owns state and decisions) → Repository / Service (data access).
- One shared `CommerceDatabase` abstraction (`FirestoreCommerceDatabase` in
  production, `MockCommerceDatabase` for tests) backs both customer and admin.
- Narrow service interfaces (`AuthRepository`, `StorageService`, …), each with a
  real implementation and a test double.
- Thin platform-channel boundaries for the native AR engine: tier, pose and
  placement decisions live in Dart; the native side only renders.

```
lib/
  app/                     App shell, routing, providers, AuthSessionState
  core/                    CommerceDatabase, models, services, theme, shared widgets
  features/
    home/ explore/ product_details/ cart/ checkout/ orders/ favorites/
    address/ profile/ auth/ onboarding/ splash/ legal/ recently_viewed/
    reviews/                 Ratings & reviews, My Reviews, report flow
    notifications/           Notification Centre, preferences, FCM registration
    virtual_try_on/          Consent → capture → upload → generate → result
    admin/                   dashboard, product_management, inventory,
                             orders_payments, ar_media_management,
                             reviews_moderation, notifications
    room_ar/                 capability (tier routing), tier1_arcore, marker_ar,
                             preview, model_delivery, preparation screen
android/app/src/main/kotlin/…/roomar/   Native AR: ARCore, CameraX, OpenCV, Filament
functions/                 Cloud Functions (TypeScript)
firestore.rules  storage.rules  firestore.indexes.json
firestore-tests/  storage-tests/        Emulator rule-test suites
scripts/                   Node admin helpers (seeding, migrations, GLB upload)
test/                      Flutter unit and widget tests
```

---

## Getting started

This section covers **running the Flutter app**. Deploying or changing the
Firebase backend is a separate task — see
[Backend setup and deployment](#backend-setup-and-deployment).

### Prerequisites

| Tool | Version / note |
|---|---|
| Flutter SDK | 3.44 (Dart `>= 3.12.2`); check with `flutter doctor` |
| Android toolchain | Android Studio or command-line SDK, a JDK 17+ (Android Studio's bundled JDK works), Android SDK platform 36; Gradle and the Android Gradle plugin are fetched by the wrapper |
| Device | A real Android phone (API 24+) is strongly recommended — camera AR and Try-On need a camera; emulators cannot exercise them |
| Node.js 22 + Firebase CLI | Only for the backend, Cloud Functions or emulator tests |
| A recent JDK | Only to run the Firebase emulators (see the Firebase CLI docs for the minimum version) |

### What the repository contains — and what you must supply

A fresh clone does **not** include git-ignored files. Supply what you need:

| Item | In the repo? | Needed for |
|---|---|---|
| `android/app/google-services.json`, `lib/firebase_options.dart`, `.firebaserc` | Yes — they point at the author's Firebase project `twin-ar-d4d75` | Building the app. Availability of that backend to third parties is not guaranteed; to use your own, run `flutterfire configure` and deploy your own backend |
| `dart_defines.json` (Stripe **test** publishable key) | **No** (git-ignored; `dart_defines.example.json` is the template) | Every build and run — without it Checkout shows "Card payment is temporarily unavailable" |
| `android/key.properties` + a release keystore | **No** (git-ignored) | Signing release builds. If absent, release builds are signed with the **debug** key |
| Google Sign-In fingerprints (SHA-1 / SHA-256) registered in your Firebase project | Your project setting | Google Sign-In on your own builds |
| Stripe secret key, webhook secret, Gemini key, `functions/.env.<projectId>` | **No** (never committed) | Backend deployment only |
| Firebase Admin credentials (ADC or service-account key) | **No** | The Node admin scripts only |

### Run on a device (Windows PowerShell)

```powershell
git clone https://github.com/TAHA-programmer/ar-ecommerce-fyp.git
cd ar-ecommerce-fyp

flutter pub get

# Create your local Stripe test-mode config (git-ignored), then edit it:
Copy-Item dart_defines.example.json dart_defines.json
notepad dart_defines.json          # set STRIPE_PUBLISHABLE_KEY to your own pk_test_... key

flutter devices                    # confirm your phone is listed
flutter run --dart-define-from-file=dart_defines.json
```

> **Every build** — debug, release or AAB — must pass
> `--dart-define-from-file=dart_defines.json`, otherwise the Stripe key is missing
> at runtime.

**Google Sign-In on your own build.** Register your keystore's fingerprints in the
Firebase console (Project settings → your Android app) and refresh
`google-services.json`. For the debug key:

```powershell
cd android
.\gradlew.bat signingReport        # prints SHA-1 / SHA-256 for each variant
cd ..
```

**Becoming an admin.** There is no in-app "invite admin". Sign up normally, then
promote exactly one account with the local script described in
`scripts/super_admin_bootstrap/README.md` (it sets the `superAdmin` custom claim
using Firebase Admin credentials on your machine).

---

## Backend setup and deployment

Running the app does not deploy anything. These steps change a **real Firebase
project** — run them only against a project you own. `.firebaserc` defaults to
`twin-ar-d4d75`; point it at yours first:

```powershell
npm install -g firebase-tools
firebase login
firebase use --add                 # choose YOUR project and alias it "default"
```

**Project requirements:** Blaze (pay-as-you-go) plan for Cloud Functions, Cloud
Scheduler and Secret Manager; Authentication (Email/Password and Google),
Firestore, Storage and Cloud Messaging enabled.

**Secrets and parameters** (never commit these):

```powershell
firebase functions:secrets:set STRIPE_SECRET_KEY       # Stripe TEST secret key (sk_test_...)
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET   # signing secret of your test-mode webhook
firebase functions:secrets:set GEMINI_API_KEY          # Google Gemini key (Virtual Try-On)
```

Create `functions\.env.<projectId>` (git-ignored) containing
`NOTIFICATIONS_ENABLED=true`. If it is missing, a non-interactive deploy fails
and an interactive one defaults notifications **off**.

**Deploy:**

```powershell
cd functions; npm ci; npm run build; cd ..
firebase deploy --only firestore:rules,firestore:indexes,storage   # rules, indexes (incl. TTL policies)
firebase deploy --only functions                                    # all 21 functions
```

To redeploy only the notification functions, deploy them **by name** with
`--force` (functions with a retry policy require it) rather than a bare deploy:

```powershell
firebase deploy --only "functions:registerDevice,functions:unregisterDevice,functions:onOrderCreatedNotify,functions:onOrderStatusNotify,functions:onProductStockNotify,functions:onReviewNotify,functions:onStripeEventNotify,functions:cleanupUserNotificationData" --force
```

**Stripe webhook.** In the Stripe Dashboard (test mode) add an endpoint at
`https://us-central1-<projectId>.cloudfunctions.net/stripeWebhook` for the
payment-intent and refund events and store its signing secret as
`STRIPE_WEBHOOK_SECRET`. The webhook rejects live-mode events.

**Seeding data.** The `scripts/` folder holds Node helpers (catalogue and category
seeding, Storage GLB upload, migrations). Each has its own `README.md`, uses
Firebase Admin credentials on your machine (for example
`gcloud auth application-default login`) and writes to a live project — read the
README and dry-run first.

---

## Testing

```powershell
flutter analyze
flutter test                              # Flutter unit + widget tests

# Rule and function suites (need Node 22, the Firebase CLI and a JDK):
cd storage-tests;   npm ci; npm test; cd ..     # Storage rules
cd firestore-tests; npm ci; npm test; cd ..     # Firestore rules
cd functions;       npm ci; npm test; npm run test:emulator; cd ..   # Functions: unit + emulator
```

Last recorded results: `flutter test` **1833 passing**, Firestore rules 321/321,
Storage rules 111/111, Cloud Functions 323 unit + 250 emulator; `flutter analyze`
and `dart format` clean. Features were also validated by hand on physical Android
devices.

---

## Building release APKs and AABs

All commands run from the repository root in **PowerShell** and need
`--dart-define-from-file=dart_defines.json`.

### Signing

Create a keystore once and keep it **outside Git**:

```powershell
keytool -genkeypair -v -keystore C:\keys\twinar-upload.jks -alias upload -keyalg RSA -keysize 2048 -validity 10000
```

Then create `android\key.properties` (git-ignored):

```properties
keyAlias=upload
keyPassword=<your key password>
storeFile=C:/keys/twinar-upload.jks
storePassword=<your store password>
```

Without this file, release builds still succeed but are signed with the debug key.

### Which artifact for whom

| Audience | Artifact | Command |
|---|---|---|
| **Google Play** | App Bundle (`.aab`) | `flutter build appbundle --release …` |
| **Supervisor / direct install (modern phone)** | arm64-v8a split APK | `flutter build apk --release --split-per-abi …` (**optimized recipe below**) |
| Older 32-bit phone | armeabi-v7a split APK | same command |
| Emulator | x86_64 split APK | same command |
| One file for any phone | arm64 + armeabi-v7a universal APK | optimized recipe, ABI filter |

An AAB is an **upload format**, not an installable file: Google Play (or
`bundletool`) derives per-device split APKs from it.

### Standard builds

```powershell
$defs = "--dart-define-from-file=dart_defines.json"
$sym  = "C:\twin_ar_symbols\1.0.0"        # keep OUTSIDE Git; one folder per release

# Play Store bundle  →  build\app\outputs\bundle\release\app-release.aab
flutter build appbundle --release --split-debug-info=$sym $defs

# Plain universal APK (all ABIs, large)
flutter build apk --release --split-debug-info=$sym $defs
```

`--split-debug-info` trims a little size and moves symbols out of the binary.
Keep the symbols folder for each release — `flutter symbolize -i <stack-trace> -d <folder>`
needs it to read crash traces. Never commit it.

### Optimized direct-install recipe

For hand-distributed APKs, two **opt-in** environment switches (read by
`android/app/build.gradle.kts`, both off by default) shrink the file:

| Variable | Effect |
|---|---|
| `TWIN_AR_COMPRESS_NATIVE_LIBS=true` | Stores native `.so` libraries compressed inside the APK (the installer extracts them) |
| `TWIN_AR_ABI_FILTERS=arm64-v8a,armeabi-v7a` | Ships only those ABIs in a **non-split** APK (Flutter's `--target-platform` does not filter OpenCV / Filament / ARCore libraries, so x86_64 would otherwise ride along) |

```powershell
$defs = "--dart-define-from-file=dart_defines.json"
$sym  = "C:\twin_ar_symbols\1.0.0-direct"

# Per-ABI APKs  →  build\app\outputs\flutter-apk\app-arm64-v8a-release.apk (supervisor), …
$env:TWIN_AR_COMPRESS_NATIVE_LIBS = "true"
flutter build apk --release --split-per-abi --split-debug-info=$sym $defs

# Single APK for phones (arm64 + armeabi-v7a); do not combine with --split-per-abi
$env:TWIN_AR_ABI_FILTERS = "arm64-v8a,armeabi-v7a"
flutter build apk --release --split-debug-info=$sym $defs

# Reset the switches so later builds use default packaging
Remove-Item Env:\TWIN_AR_COMPRESS_NATIVE_LIBS, Env:\TWIN_AR_ABI_FILTERS -ErrorAction SilentlyContinue
```

> **Never use these switches for the Play AAB.** Play already downloads compressed
> and keeps native libraries uncompressed and page-aligned on the device.

### Measured sizes (this project)

| Artifact | Size |
|---|---|
| Direct-install arm64 APK (optimized) | ≈ 62.9 MB |
| Direct-install armeabi-v7a APK (optimized) | ≈ 60.7 MB |
| Release AAB (upload file) | ≈ 157 MB |
| Play download to an arm64 phone (bundletool estimate) | ≈ 59.7 MB |
| Installed size of the arm64 APK on a phone (Settings) | ≈ 136 MB |

The installed size is larger than the APK because Android also keeps the extracted
native libraries (OpenCV, Flutter engine, Filament), compiled code and app data.
These are measurements of this build on the author's setup, not guarantees.

---

## Security model

- **Roles** are custom claims (`superAdmin`); email-based admin detection is never used.
- **Rules** are hardened and covered by emulator test suites; writes are
  validated for field shape, type and size.
- **Orders, payments and reviews** are `create: if false` for every direct client
  write — created exclusively by Cloud Functions via the Admin SDK, which verify
  eligibility first (for example a review requires a genuinely delivered order).
- **Stock** is reserved in an atomic Firestore transaction **before** any Stripe
  PaymentIntent exists; the webhook restores it once on failure and a scheduled
  sweep releases abandoned reservations.
- **Stripe is test mode only.** The secret key lives in Firebase Secret Manager
  (never in the repo); only the publishable `pk_test_` key reaches the app, via
  `--dart-define` from a git-ignored file.
- **Reviews** never expose an email, phone or account details — only a masked
  display name computed server-side.
- **Notifications:** FCM is sent only from Cloud Functions (no server key in the
  app, no topics); tokens and the admin ledger are server-only; the inbox is
  server-written (clients can only mark their own rows read or delete them); a
  tapped payload can only open a pre-approved screen and is dropped for the wrong
  account or role.
- **AR / garment assets** require signed-in reads (approved products only for
  customers), super-admin writes, strict content-type and size gates, and
  provenance metadata (SHA-256 + version).

---

## Project status

**Delivered**

- Full customer storefront and admin panel on a Firestore backend
- Stripe test-mode checkout with server-side order creation and atomic stock reservation
- Email/password and Google authentication with custom-claim roles
- **Room AR** across three tiers (ARCore, OpenCV marker, 3D preview) with secure
  Storage model delivery and an admin model-management workflow
- **Virtual Try-On** with an admin garment pipeline and a server-side Gemini function
- **Ratings and reviews** with full admin moderation
- **Dynamic Home** content driven by real Firestore signals
- **Push notifications (FCM) v1** — Notification Centre, preferences, customer and
  admin alerts, safe deep links, device registration with cleanup, TTL retention
- Optimized, signed release builds for direct install and Google Play

**Future work**

- Broaden the validated AR model catalogue to more products
- Wider cross-device validation
- Google Play App Signing: register the Play-managed signing fingerprints for Google Sign-In
- Notification extras left out of v1: back-in-stock, price-drop and promotional
  alerts, an admin digest, Firebase App Check, localisation
- iOS support

---

## Support

Questions or issues: **twinar.support@gmail.com**, or use **Profile → Help &
Support → Contact Support** in the app, which opens a prepared email to the same
address.

---

## Author

**Taha Fayyaz** — Final Year Project (FYP-2).

Built with Flutter, Firebase, OpenCV and Google Filament.

_© 2026 Taha Fayyaz. All rights reserved._
