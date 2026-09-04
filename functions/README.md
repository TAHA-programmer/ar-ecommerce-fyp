# TWin AR Cloud Functions

Node / TypeScript Cloud Functions for **Phase 8.13 - Real Stripe Sandbox
integration with trusted server-side stock reservation**. Separate toolchain
from the Flutter app; not part of `flutter build` / `flutter test`.

**Status: Phase 8.13 (all six subphases) DEPLOYED AND PHYSICALLY APPROVED /
COMPLETE (2026-08-28).** This is a **Stripe test-mode (Sandbox)** deployment -
no live-mode account, no real-money settlement.

- **Region:** `us-central1` (see `src/config.ts`)
- **Runtime:** Node 22 (2nd-gen functions)
- **Project:** `twin-ar-d4d75` (see `../.firebaserc`)

## Deployed functions

| Subphase | Function | Summary |
|---|---|---|
| 8.13.2 | `createPaymentIntent` (callable) | Firebase-auth required. Strict input validation (product references / variant labels / quantities / `addressId` / `idempotencyKey` only - never client prices, totals, stock or `userId`). Resolves authoritative `products` + the user-owned address from Firestore, aggregates by `productId`, then **an atomic Firestore transaction reserves (decrements) stock and writes the server-owned `checkoutSessions` doc BEFORE any PaymentIntent exists**. Then a PKR Stripe **test-mode** PaymentIntent with a deterministic idempotency key. Full compensation (stock restore + session close) on any Stripe failure. The server re-computes and owns every total; the small-cart discount is clamped so the Firestore monetary invariants always hold. |
| 8.13.3 | `stripeWebhook` (2nd-gen HTTPS) | Raw-body Stripe signature verification, sandbox-only (rejects `livemode`), and authoritative handling of `payment_intent.succeeded` / `payment_failed` / `canceled`. Verifies the PaymentIntent id / metadata / user / currency / amount against the session before any change. On success: atomically + idempotently creates the final `orders`/`payments` from the **session snapshots** (never from event metadata) and marks the session `succeeded` with the real `orderId`. On a closed attempt: **cancels the PaymentIntent first** (8.13.4 hardening) then restores every reserved quantity **exactly once**. If a payment lands after its reservation was released: an **idempotent sandbox refund**. Idempotency via the server-only `stripeEvents/{eventId}` ledger + deterministic `ord_<hex>` / `pay_<hex>` ids. |
| 8.13.4 | `releaseExpiredReservations` (scheduled, every 5 min) | Bounded batch sweep of expired `reserved` sessions using the `(status, expiresAt)` index. Per session: inspects the authoritative PaymentIntent - `succeeded` -> finalize the order; `processing` -> defer; unpaid-and-cancellable -> cancel then restore stock exactly once and mark the session `expired`. Reconciles a session whose PI id was never persisted via the deterministic Stripe idempotency key. Every mutation re-checks session state in its transaction, so overlapping/duplicate runs are safe. |

## Flutter / rules side of Phase 8.13 (not in this folder)

| Subphase | Delivered |
|---|---|
| 8.13.5 | Android `flutter_stripe` PaymentSheet wired to `createPaymentIntent`; the app waits for the authoritative `checkoutSessions/{id}` result and only clears the cart + opens Order Result after the webhook marks the session `succeeded` with a real `orderId`. Publishable key via `--dart-define` only. Minimal Android host changes (`FlutterFragmentActivity`, MaterialComponents NormalTheme, Kotlin `jvmTarget = 17`). Release-build R8 workaround for `flutter_stripe`'s unused card-issuing "push provisioning" dependency (`android/app/build.gradle.kts` module exclude + `android/app/proguard-rules.pro` `-dontwarn`). |
| 8.13.6 | **Final Firestore security cutover** - `orders`/`payments` `create` is now `if false` for every client (customer and superAdmin); these functions (via the Admin SDK) are the only writers. The Phase 8.9 client-side `submitOrderWithPayment` transaction, `OrderIdGenerator`, `recordOrderStockDecrement`, `_unmigrated` mock and the dead `isValidOrderCreate` / `orderMatchesPayment` rule functions were removed. Added an app-level late-success cart-line reconciliation (`CheckoutCartReconciler`). |

## Cloud Scheduler (Phase 8.13.4)

Deploying `releaseExpiredReservations` auto-creates a Cloud Scheduler job
(`firebase-schedule-releaseExpiredReservations-us-central1`) and a Pub/Sub
topic. Requires the **Cloud Scheduler API** to be enabled on the project
(Blaze enables it; `firebase deploy` prompts if it isn't). Cost: the first
**3 scheduler jobs per month are free**; this is 1 job. Function invocations
(~8,640/month at every-5-min) are well inside the 2M-call free tier. Expected
incremental cost: **~$0**.

## Secrets (never committed, never pasted into chat, no value recorded)

Values are set only through Firebase Secret Manager by the project owner:

```bash
firebase functions:secrets:set STRIPE_SECRET_KEY      # 8.13.2 - version 1 in use
firebase functions:secrets:set STRIPE_WEBHOOK_SECRET   # 8.13.3 - set AFTER registering the endpoint (below)
```

**`STRIPE_WEBHOOK_SECRET` history:** the first stored version was the wrong
signing secret and every delivery failed with an "invalid signature" HTTP 400.
The correct `whsec_...` (from the existing Stripe Sandbox webhook endpoint)
was stored as **version 2**, `stripeWebhook` was redeployed, and the stale
version 1 was removed. Deliveries now return HTTP 200. No secret value is
recorded anywhere in the repo or the reference pack.

- `createPaymentIntent` is bound to `STRIPE_SECRET_KEY` only.
- `stripeWebhook` is bound to **both** `STRIPE_WEBHOOK_SECRET` (verify the
  signature - HMAC, never touches the API key) **and** `STRIPE_SECRET_KEY`
  (Phase 8.13.4: cancel a still-open PaymentIntent before restoring stock;
  refund a payment that landed after its reservation was released).
- `releaseExpiredReservations` is bound to `STRIPE_SECRET_KEY` only
  (retrieve / cancel / refund). It does not verify signatures, so it does not
  need `STRIPE_WEBHOOK_SECRET`.

The Flutter **publishable** key (`pk_test_...`) is supplied later through
secure local build configuration, never a source file. Source references
secret **names** only (`src/config.ts`).

## Registering the sandbox webhook (Phase 8.13.3 - DONE; kept for reference / redeploys)

1. Deploy the function: `firebase deploy --only functions:stripeWebhook --project twin-ar-d4d75`
   (it will print the HTTPS URL, e.g. `https://us-central1-twin-ar-d4d75.cloudfunctions.net/stripeWebhook`).
2. Stripe **test-mode** Dashboard -> Developers -> Webhooks -> Add endpoint:
   - URL: the deployed function URL
   - Events: `payment_intent.succeeded`, `payment_intent.payment_failed`, `payment_intent.canceled`
   - Copy the endpoint's **Signing secret** (`whsec_...`).
3. `firebase functions:secrets:set STRIPE_WEBHOOK_SECRET --project twin-ar-d4d75`
   and paste the `whsec_...` value at the prompt (in your terminal only).
4. Redeploy so the function picks up the secret:
   `firebase deploy --only functions:stripeWebhook --project twin-ar-d4d75`.
5. Local end-to-end testing without deploying: `stripe listen --forward-to
   http://localhost:5001/twin-ar-d4d75/us-central1/stripeWebhook` (the CLI
   prints a temporary `whsec_...` to use in a local `.env` **that is
   git-ignored**).

## Commands

```bash
cd functions
npm install
npm run build          # tsc -> lib/ (CommonJS)
npm run lint           # tsc --noEmit for src + test
npm test               # vitest - pure unit tests (no emulator, no network)
npm run test:emulator  # firebase emulators:exec + vitest - real Firestore emulator, MOCK Stripe
```

Automated tests never call live or sandbox Stripe. `createPaymentIntent`
tests inject a fake Stripe client; `stripeWebhook` tests sign mock events
with `stripe.webhooks.generateTestHeaderString` and a fake local secret
(`test/helpers/emulator.ts`).

## Final verification (Phase 8.13 close-out, 2026-08-28)

| Suite | Command | Result |
|---|---|---|
| Functions type-check | `npm run lint` | clean |
| Functions unit | `npm test` | **89 / 89** |
| Functions emulator (real Firestore, mock Stripe) | `npm run test:emulator` | **63 / 63** |

Alongside (Flutter / rules side): `flutter test` **736 / 736**, `firestore-tests`
**236 / 236**, `flutter analyze` clean. `firestore.rules` deployed to
`twin-ar-d4d75` for the 8.13.6 cutover; all three functions deployed to
`us-central1`; sandbox webhook endpoint registered; `firestore.indexes.json`
carries the `checkoutSessions (status, expiresAt)` index. Android physical
testing passed on 2026-08-28.
