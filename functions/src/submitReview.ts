import { Timestamp } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { FUNCTIONS_REGION, REVIEW_EDIT_WINDOW_MS } from "./config";
import { db, productStatsDoc, reviewDoc, userDoc } from "./lib/firestore";
import {
  applyRatingDelta,
  ratingAggregateFromStatsData,
  statsFieldsFromAggregate,
} from "./lib/reviews/aggregate";
import { maskReviewerDisplayName } from "./lib/reviews/authorDisplayName";
import { findQualifyingDeliveredOrder } from "./lib/reviews/eligibility";
import {
  errEditWindowExpired,
  errInternal,
  errNotEligible,
  errUnauthenticated,
  logUnexpected,
} from "./lib/reviews/errors";
import { reviewDocId } from "./lib/reviews/model";
import { parseSubmitReviewRequest } from "./lib/reviews/validation";

/**
 * `submitReview` (callable) - Ratings/Reviews v1, Stage 2.
 *
 * Creates a NEW review, or EDITS the caller's existing one for the same
 * product - the deterministic `reviews/{uid}_{productId}` doc id (see
 * `lib/reviews/model.ts#reviewDocId`) makes the two the SAME operation, so
 * there is no separate "edit" request shape and no way to end up with two
 * documents for one (user, product) pair (v1 §0 decision 2: "one review per
 * user per product, even after repeat purchases").
 *
 * Flow:
 *   1. Parse + validate the request (pure, no I/O) - rejects a malformed
 *      request before any Firestore read.
 *   2. Re-verify eligibility server-side via `findQualifyingDeliveredOrder`
 *      (the Admin SDK bypasses `firestore.rules`, so THIS is the real gate -
 *      never the client's own `isEligibleToReview` read, which is
 *      display-only).
 *   2b. Resolve + mask the CALLER'S OWN `users/{uid}.displayName` via the
 *      Admin SDK into `authorDisplayName` (see `lib/reviews/authorDisplayName.ts`)
 *      - this is the ONLY place a customer's real profile is ever read to
 *      show a name on a review (their own), and it is stored directly on
 *      the review document as an already-safe snapshot. No client ever
 *      reads another customer's `users/{uid}` profile to resolve a review
 *      author's name - `firestore.rules` denies that (owner/admin-only
 *      read), and no code path in this app attempts it.
 *   3. ONE transaction: read the existing review (if any) + the product's
 *      `productStats` doc, apply the rating-aggregate delta (reversing the
 *      OLD rating first on an edit - see `lib/reviews/aggregate.ts` - so an
 *      edit is never double-counted as a second review), then write both.
 *      A resubmission past the `REVIEW_EDIT_WINDOW_MS` edit window (measured
 *      from the review's ORIGINAL `createdAt`, never reset by a prior edit)
 *      is refused before either write is applied.
 *
 * Only a currently-`published` review's rating counts toward the aggregate
 * (v1 §0 decision 15) - reversing an already-`hidden`/`rejected` review's
 * contribution is skipped (it was never counted in the first place) -
 * forward-compatible with Stage 3's moderation, which is the only way a
 * review can be non-`published` (nothing in Stage 2 itself creates one).
 */

export interface SubmitReviewResult {
  reviewId: string;
  edited: boolean;
}

export interface SubmitReviewHandlerInput {
  authUid: string | undefined;
  data: unknown;
  /** Injectable clock for tests - production uses the real wall clock. */
  now?: () => number;
}

export async function submitReviewHandler(
  input: SubmitReviewHandlerInput,
): Promise<SubmitReviewResult> {
  const nowMs = (input.now ?? Date.now)();

  if (!input.authUid) {
    throw errUnauthenticated();
  }
  const uid = input.authUid;

  const request = parseSubmitReviewRequest(input.data);

  // Eligibility FIRST, outside the transaction - a request that was never
  // going to succeed touches no other document.
  const orderId = await findQualifyingDeliveredOrder(uid, request.productId);
  if (!orderId) {
    throw errNotEligible();
  }

  // Resolve + mask the CALLER'S OWN profile display name here, once, via
  // the Admin SDK (bypasses `firestore.rules`' owner/admin-only
  // `users/{uid}` read rule) - this is the ONLY place a customer's real
  // profile is ever read to show a name on a review, and only their own.
  // The already-safe masked result is what gets stored on the review doc
  // below; no other reader (client or otherwise) ever needs to look up
  // `users/{uid}` for this. Re-resolved on every submit (create AND edit),
  // so a later profile-name change is reflected on the next edit.
  const profileSnap = await userDoc(uid).get();
  const authorDisplayName = maskReviewerDisplayName(
    (profileSnap.data()?.displayName as string | undefined) ?? null,
  );

  const reviewId = reviewDocId(uid, request.productId);

  try {
    return await db().runTransaction<SubmitReviewResult>(async (tx) => {
      const reviewRef = reviewDoc(reviewId);
      const statsRef = productStatsDoc(request.productId);
      const [reviewSnap, statsSnap] = await Promise.all([tx.get(reviewRef), tx.get(statsRef)]);

      const currentAggregate = ratingAggregateFromStatsData(statsSnap.data());

      if (reviewSnap.exists) {
        const existing = reviewSnap.data() as Record<string, unknown>;
        const createdAt = existing.createdAt as Timestamp;
        if (nowMs - createdAt.toMillis() > REVIEW_EDIT_WINDOW_MS) {
          throw errEditWindowExpired();
        }

        const existingRating = existing.rating as number;
        const wasPublished = existing.status === "published";
        const reversed = wasPublished
          ? applyRatingDelta(currentAggregate, existingRating, -1)
          : currentAggregate;
        const nextAggregate = applyRatingDelta(reversed, request.rating, 1);

        tx.set(statsRef, statsFieldsFromAggregate(nextAggregate), { merge: true });
        tx.update(reviewRef, {
          rating: request.rating,
          title: request.title,
          body: request.body,
          authorDisplayName,
          // `Timestamp.fromMillis(nowMs)`, not `FieldValue.serverTimestamp()` -
          // every review timestamp uses the SAME injected clock as the
          // edit-window check itself, so the two can never disagree (a
          // sentinel resolves to the real wall clock regardless of what
          // `input.now` says, which would make the edit-window check
          // untestable and, in a hypothetical clock-skew scenario, wrong).
          editedAt: Timestamp.fromMillis(nowMs),
        });
        return { reviewId, edited: true };
      }

      const nextAggregate = applyRatingDelta(currentAggregate, request.rating, 1);
      tx.set(statsRef, statsFieldsFromAggregate(nextAggregate), { merge: true });

      tx.create(reviewRef, {
        productId: request.productId,
        userId: uid,
        authorDisplayName,
        orderId,
        rating: request.rating,
        title: request.title,
        body: request.body,
        status: "published",
        reportCount: 0,
        flaggedForReview: false,
        // Same reasoning as the edit path's `editedAt` above - the
        // edit-window check reads this back, so it must use the identical
        // injected clock, never a serverTimestamp sentinel.
        createdAt: Timestamp.fromMillis(nowMs),
        editedAt: null,
        moderatedAt: null,
        moderatedBy: null,
        moderationReason: null,
      });
      return { reviewId, edited: false };
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logUnexpected("submitReview: unexpected failure", err, {
      uid,
      productId: request.productId,
    });
    throw errInternal();
  }
}

export const submitReview = onCall(
  { region: FUNCTIONS_REGION, memory: "256MiB", timeoutSeconds: 30 },
  (request) => submitReviewHandler({ authUid: request.auth?.uid, data: request.data }),
);
