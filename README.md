# TWin AR — E-Commerce App with Augmented Reality

A production-grade Android e-commerce application built with Flutter and Firebase,
featuring an **in-room Augmented Reality product preview**, **camera-based Virtual
Try-On for clothing**, a real Stripe checkout, a Ratings & Reviews system,
**push notifications (Firebase Cloud Messaging)**, and a full admin management
panel.

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
- [Push Notifications (FCM)](#push-notifications-fcm)
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
  virtually before buying. Order, refund and review-moderation updates arrive
  as optional push notifications and are always kept in an in-app
  Notification Centre.
- **Super-admins** manage products, categories, inventory stock, orders &
  payments, customer reviews, and upload / validate / version / enable-disable /
  delete the 3D models and garment assets that power the AR and Virtual Try-On
  experiences — all from an in-app admin panel gated by Firebase custom claims.
- The backend is **real Firebase** (Auth, Firestore, Storage, Cloud Functions,
  Cloud Messaging)
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
- **Notification Centre & preferences** — a server-written inbox of order
  (placed / confirmed / shipped / delivered / cancelled), payment-refund and
  review-moderation updates, with unread badge on the Home/Explore bell, mark
  read / mark all read / swipe to delete, and per-category push switches
  (see [Push Notifications](#push-notifications-fcm))
- Profile, delivery address book (single authoritative default), favourites,
  My Reviews — all cross-device synced
- Help & Support (FAQ covering ordering, AR, Try-On, reviews, payments, notifications) with a
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
  count, and never shown when there's nothing to flag). It stays a live,
  state-derived view; **push alerts** (new order, low / out of stock, flagged
  review, payment issue) complement it and deep-link into the relevant screen
  — they are not stored as an Admin inbox
- Account menu with a real, confirmed sign-out flow — no placeholder tiles, no
  "mock" labels

### Backend (Firebase)
- Custom-claim (`superAdmin`) role authorization — never email-based
- Hardened `firestore.rules` + `storage.rules` with full emulator test suites
- Cloud Functions (Node 22, `us-central1`) — **21 live in total**: 13 existing
  plus the 8 notification functions below:
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
  - **Notifications (FCM)**: `registerDevice`, `unregisterDevice` (callables),
    `onOrderCreatedNotify`, `onOrderStatusNotify`, `onProductStockNotify`,
    `onReviewNotify`, `onStripeEventNotify` (Firestore triggers) and
    `cleanupUserNotificationData` (Auth-deletion cleanup, a sibling of the
    Try-On and Reviews cleanups). All triggers sit behind a
    `NOTIFICATIONS_ENABLED` kill-switch.
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

## Push Notifications (FCM)

Server-driven push notifications over **Firebase Cloud Messaging**, built so a
push is only ever a *convenience* — the in-app state is always the source of
truth.

**What is sent**

| Audience | Events |
|---|---|
| Customer | Order confirmed, shipped, delivered, cancelled; a payment refunded because a reservation was lost; a review hidden / not published by moderation |
| Customer (inbox only, no push) | Order placed; review restored |
| Admin | New paid order; product low stock (crossing into 1–5) and out of stock; a review flagged by repeated reports; a payment issue |

Customer notices never include an address, items or amounts (only a short order
reference), and a cancellation never promises a refund. Stock alerts use a
cooldown so flapping around the threshold cannot spam.

**Customer experience**
- **Notification Centre** (bell on Home/Explore, plus Profile → Notifications):
  newest first, grouped by day, with loading / empty / error-with-retry states
  and an "off" banner when the OS permission is not granted. It works offline
  from the Firestore cache.
- **Preferences** (Notification settings): customers can switch **Order
  updates** and **Reviews & moderation** off; Admin has four switches (new
  orders, stock, moderation, payments). Switching a category off stops only the
  *push* — the Notification Centre still records the update.
- **Permission** (Android 13+ `POST_NOTIFICATIONS`) is requested only at a
  relevant moment — after the first order, from Settings, or as a one-time Admin
  explainer — never at app launch, and a "Not now" is remembered.
- **Foreground / background / terminated:** a push while the app is open shows
  a tappable in-app banner (no duplicate system notification); otherwise the OS
  renders it from the FCM `notification` payload on one of four Android
  channels — *Order updates* (high), *Account & reviews* (low),
  *Store alerts* (high), *Stock & moderation* (default).
- **Safe deep links:** a payload is strictly validated (version, allow-listed
  type, audience, id shape) and mapped to a **hard-coded** destination — it never
  carries a route or URL. A notification for a different signed-in account, or
  an Admin destination for a non-admin, is dropped; a tap during splash/login is
  held, re-validated against the current session, then opened on top of the
  stack.

**Device registration & cleanup**
- The app registers its FCM token through the `registerDevice` callable; the
  **server stamps the role from the verified ID-token claim** (never the request
  body). Tokens live in a **server-only** `deviceTokens` collection keyed by the
  token's SHA-256, capped at 10 devices per user, and a token re-registered by
  another account moves ownership (shared-device safe).
- On logout the app asks the server to remove the token (best-effort,
  time-boxed) and always invalidates the local token; a leftover record is
  removed by failed-send pruning or its 60-day TTL. Deleting an account also
  deletes its tokens, inbox and preferences.

**Data model, rules & TTL**
- `users/{uid}/notifications/{dedupeKey}` — server-written inbox; deterministic
  ids make every trigger idempotent. Clients may only set `readAt` (to the
  server time) or delete their own rows.
- `users/{uid}/notificationSettings/prefs` — owner-writable booleans (missing =
  on; admin keys accepted only from a super-admin).
- `deviceTokens` and `notificationEvents` (admin dedupe/cooldown ledger) have
  **no client access**.
- Firestore **TTL policies** on `expireAt`: device tokens (60 days), inbox rows
  (90 days), ledger (7 days).
- FCM is sent only from Cloud Functions (Admin SDK, direct-to-token — no topics,
  no server key in the app). Dead tokens are pruned; transient failures never
  delete a device.

**Deployment requirement (kill-switch).** The 8 functions read a
`NOTIFICATIONS_ENABLED` boolean parameter. Deploys are non-interactive, so the
project's git-ignored `functions/.env.<projectId>` file must define that
parameter; if it is missing, a non-interactive deploy fails and an interactive
one defaults the flag **off**. Deploy the notification functions **by name** with
`--force` (functions with a retry policy require it) and never with a bare
`firebase deploy` that would touch the other 13.

```bash
firebase deploy --only functions:registerDevice,functions:unregisterDevice,\
functions:onOrderCreatedNotify,functions:onOrderStatusNotify,\
functions:onProductStockNotify,functions:onReviewNotify,\
functions:onStripeEventNotify,functions:cleanupUserNotificationData --force
```

Push delivery is **best-effort** by nature (Doze, battery savers, a
force-stopped app, no network); nothing in the app depends on a push arriving.

---

## Tech Stack

- **Flutter** (Dart SDK `^3.12.2`; developed on Flutter 3.44 / Dart 3.12), **Provider** for state
- **Firebase**: Auth (Email/Password + Google Sign-In), Cloud Firestore,
  Storage, Cloud Functions (Node 22 / TypeScript), Cloud Messaging (FCM)
- **Stripe** `flutter_stripe` (test mode only — no live account)
- **Google Gemini** — server-side Virtual Try-On image generation
- **Native Android (Kotlin)** for AR: CameraX, OpenCV 4.12 (ArUco + `solvePnP`),
  Google Filament (glTF rendering), platform channels
- `google_sign_in`, `url_launcher`, `file_picker`, `image_picker`,
  `firebase_messaging`, `permission_handler`, `printing` / `pdf`, `path_provider`, `crypto`,
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
    notifications/             Notification Centre, preferences, FCM registration,
                                payload router / navigator, lifecycle
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
android/app/src/main/kotlin/com/tahafayyaz/twin_ar/NotificationChannels.kt
                             The four FCM notification channels
functions/                   Cloud Functions (Stripe, reviews, Try-On, home stats,
                             notifications — lib/notifications/)
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

Current status: `flutter test` **1828 passing**, Firestore rules **321/321**,
Storage rules **111/111**, Cloud Functions **323/323** unit + **250/250**
emulator; `flutter analyze` clean; `dart format` clean; `flutter build apk`
(debug, release/R8, split-per-abi) all green. The FCM Notifications v1 feature
added 337 of these tests and was validated physically on an Android 13 device
(customer and Admin flows, background / foreground / release builds).

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
- **Notifications:** FCM is sent only from Cloud Functions (no server key or
  credentials in the app, no topics); device tokens and the admin ledger are
  **server-only** collections; the inbox is server-written and clients can only
  mark their own rows read or delete them; the device role is stamped from the
  verified ID-token claim, and admin pushes are re-verified against the live
  claim at send time; a tapped payload can only select a pre-approved screen and
  is dropped for the wrong account or role.
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
- **Push Notifications (FCM) v1** — customer Notification Centre and
  preferences, customer/Admin push alerts, foreground banner + background
  notifications on four Android channels, safe deep links, server-stamped device
  registration with logout/account-deletion cleanup, TTL retention, and a
  deploy-time kill-switch; deployed live (21 Cloud Functions in total) and
  validated on-device
- Functional Contact Support (opens a prepared email to a real, monitored
  mailbox), and Profile legal/help content kept accurate against actual app
  behaviour

**Future Work**
- Broaden the validated AR model catalogue to further products
- ARCore markerless (Tier 1) runtime, alongside a certified test device
- Wider cross-device validation matrix
- Google Play App Signing / Play-distributed AAB fingerprint registration
- Notification extras deliberately left out of v1: back-in-stock, price-drop and
  promotional alerts, daily Admin digest, Firebase App Check, localisation
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
- **Push delivery is best-effort.** A failed send is not retried, a
  force-stopped app receives nothing, and battery savers can delay delivery; the
  Notification Centre / My Orders / Admin screens are the source of truth.
- **The notification kill-switch is deploy-time configuration** kept in a
  git-ignored `functions/.env.<projectId>` file; redeploying those functions
  without it fails (non-interactive) or silently defaults the feature off
  (interactive) — see [Push Notifications](#push-notifications-fcm).
- Notifications were validated on one Android 13 phone (plus a second Admin
  session). **Not exercised:** two devices on one customer account, Android 12
  or lower, and an explicit offline-logout run. A logout without connectivity
  leaves a stale server token that is cleaned by failed-send pruning or the
  60-day TTL. The per-recipient send cap is per function instance.
- Users still on a pre-notification app build accumulate inbox rows they cannot
  see and receive no pushes.
- The Admin Notifications screen lists pending orders and *low* stock (1–5);
  an out-of-stock *push* is sent but out-of-stock products are listed on the
  Inventory screen, not that list.

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
