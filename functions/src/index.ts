/**
 * TWin AR Cloud Functions
 * =======================
 * Phase 8.13 - Real Stripe Integration with trusted server-side stock
 * reservation. Region: us-central1 (see `config.ts`).
 *
 * Implemented so far:
 *   - Phase 8.13.2: `createPaymentIntent` (callable) - auth + strict input
 *     validation, server-authoritative products/prices/totals, aggregation
 *     by productId, atomic stock reservation + server-owned
 *     `checkoutSessions` document, Stripe PKR sandbox PaymentIntent, and
 *     compensation (stock restore + session close) on any Stripe failure.
 *   - Phase 8.13.3: `stripeWebhook` (HTTPS) - raw-body signature
 *     verification, sandbox-only enforcement, authoritative handling of
 *     `payment_intent.succeeded` / `payment_failed` / `canceled`. Idempotency
 *     via the server-only `stripeEvents/{eventId}` ledger + deterministic
 *     order / payment ids.
 *   - Phase 8.13.4: `releaseExpiredReservations` (scheduled, every 5 min) -
 *     inspects the authoritative PaymentIntent for each expired `reserved`
 *     session and, only when a payment can no longer succeed, cancels it and
 *     restores the reserved stock exactly once (marking the session
 *     `expired`); finalizes a succeeded payment into an order; defers one
 *     still in flight. Also hardens the webhook `payment_failed` path
 *     (cancel-before-restore) and closes the "paid after release" gap with an
 *     idempotent sandbox refund.
 *
 * NOT yet implemented (later, separately-approved subphases):
 *   - Phase 8.13.5: Flutter PaymentSheet integration; retire the Phase 8.9
 *     interim checkout path.
 *   - Phase 8.13.6: tighten `orders`/`payments` `create` rules to
 *     Cloud-Function-only.
 */
import { initializeApp } from "firebase-admin/app";

initializeApp();

export { createPaymentIntent } from "./createPaymentIntent";
export { stripeWebhook } from "./stripeWebhook";
export { releaseExpiredReservations } from "./releaseExpiredReservations";

// Phase 9.3 "Dynamic Home Content" Stage 2 - server-maintained Home ordering
// aggregates (`productStats/{productId}`). `unitsSold` is bumped inside the
// existing exactly-once webhook finalize path; these two Firestore triggers
// keep it and `favoriteCount` correct on cancellation / favouriting, each
// exactly idempotent. NOT deployed yet.
export { adjustStatsOnOrderCancel } from "./adjustStatsOnOrderCancel";
export { adjustFavoriteCount } from "./adjustFavoriteCount";

// Phase 9.3 "Virtual Try-On" Stage 4 - server-side generation behind a
// provider abstraction (LOCKED to Gemini `gemini-2.5-flash-image`, D2), with
// per-user + global rate limiting (D9), unconditional person-photo deletion
// (D4), a 24h result-media TTL safety sweep, and Auth-deletion cleanup. NOT
// deployed yet - local implementation + test pass only.
export { generateTryOn } from "./generateTryOn";
export { cleanupExpiredTryOnMedia } from "./cleanupExpiredTryOnMedia";
export { cleanupUserTryOnData } from "./cleanupUserTryOnData";

// Ratings/Reviews v1 (`24_RATINGS_REVIEWS_FEEDBACK_PLAN.md`), Stage 2 -
// `submitReview` (create-or-edit) and `deleteReview`, both transactionally
// maintaining the `productStats` rating aggregate. NOT deployed yet - local
// implementation + test pass only (rules/indexes for `reviews`/
// `reviewReports` are Stage 4; `reportReview`/`moderateReview` are Stage 3).
export { submitReview } from "./submitReview";
export { deleteReview } from "./deleteReview";

// Stage 3 - `reportReview` (unique-reporter counting, threshold flagging,
// never auto-hides) and `moderateReview` (admin-only hide/restore/reject
// with a required reason + audit stamp). NOT deployed yet - local
// implementation + test pass only (rules/indexes are Stage 4).
export { reportReview } from "./reportReview";
export { moderateReview } from "./moderateReview";

// Stage 9 - Auth-deletion cleanup, a sibling to `cleanupUserTryOnData`
// (same `auth.user().onDelete()` event, both fire independently): hard-
// deletes every review the deleted user authored and reverses each
// `published` one out of `productStats`. NOT deployed yet - local
// implementation + test pass only.
export { cleanupUserReviewsData } from "./cleanupUserReviewsData";
