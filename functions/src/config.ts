import { defineSecret } from "firebase-functions/params";

/**
 * Cloud Functions region for every TWin AR function (approved: us-central1).
 * Firestore is in the `nam5` multi-region; `us-central1` is the standard,
 * lowest-latency Functions region for it.
 */
export const FUNCTIONS_REGION = "us-central1";

/**
 * Presentment + settlement currency for every PaymentIntent. `Rs` == PKR
 * (reference pack Decisions Log). PKR is a standard two-decimal currency
 * (not zero-decimal) - see `lib/currency.ts`.
 */
export const ORDER_CURRENCY = "pkr";

/**
 * Tag written to PaymentIntent metadata (`appPhase`) so a PaymentIntent
 * created by this subphase is identifiable in the Stripe dashboard and by
 * the Phase 8.13.3 webhook. Not security-sensitive.
 */
export const PAYMENT_INTENT_PHASE_TAG = "twin_ar_8_13_2";

/**
 * Phase 8.13.4 - expired-reservation sweep (`releaseExpiredReservations`).
 *
 * Runs every 5 minutes. Each run processes at most `BATCH_SIZE` expired
 * `reserved` sessions using the `(status, expiresAt)` composite index; if
 * there are more, the next run continues (the work is idempotent, so a
 * missed or overlapping run is harmless).
 */
export const RESERVATION_SWEEP_SCHEDULE = "every 5 minutes";
export const RESERVATION_SWEEP_BATCH_SIZE = 20;

/**
 * Secret Manager secret NAMES ONLY.
 *
 * The secret VALUES are provided out-of-band by the project owner:
 *   firebase functions:secrets:set STRIPE_SECRET_KEY
 *   firebase functions:secrets:set STRIPE_WEBHOOK_SECRET   (Phase 8.13.3)
 *
 * They are bound to individual functions at deploy time via
 * `secrets: [stripeSecretKey]` and read at runtime with `.value()`. A secret
 * value is NEVER written to source, a committed `.env`/`.runtimeconfig.json`,
 * a log line, a test fixture, or documentation.
 *
 * `stripeWebhookSecret` is declared here for a single source of truth but is
 * only consumed by the webhook function added in the later Phase 8.13.3
 * subphase.
 */
export const stripeSecretKey = defineSecret("STRIPE_SECRET_KEY");
export const stripeWebhookSecret = defineSecret("STRIPE_WEBHOOK_SECRET");
