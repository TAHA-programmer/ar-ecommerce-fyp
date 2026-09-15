import { HttpsError, onCall } from "firebase-functions/v2/https";

import { FUNCTIONS_REGION } from "./config";
import { db, productStatsDoc, reviewDoc } from "./lib/firestore";
import {
  applyRatingDelta,
  ratingAggregateFromStatsData,
  statsFieldsFromAggregate,
} from "./lib/reviews/aggregate";
import { errInternal, errUnauthenticated, logUnexpected } from "./lib/reviews/errors";
import { reviewDocId } from "./lib/reviews/model";
import { parseDeleteReviewRequest } from "./lib/reviews/validation";

/**
 * `deleteReview` (callable) - Ratings/Reviews v1, Stage 2.
 *
 * Deletes the CALLER'S OWN review for the given product. There is no
 * "reviewId" parameter and therefore no way to ever address another user's
 * review through this callable - the document is always the deterministic
 * `reviews/{uid}_{productId}` derived from the CALLER's own auth uid (see
 * `lib/reviews/model.ts#reviewDocId`), so an ownership check is structurally
 * unnecessary rather than merely enforced (Admin removal of someone else's
 * review is the separate, admin-claim-gated `moderateReview` callable,
 * Stage 3). No time limit (v1 §0 decision 7).
 *
 * A product with no existing review for this caller is a harmless success
 * no-op (mirrors `MockReviewsRepository.deleteReview`) - deleting something
 * that was never there is not an error.
 *
 * The same transaction reverses the review's rating out of `productStats`
 * ONLY if it was currently `published` (v1 §0 decision 15) - a
 * `hidden`/`rejected` review (Stage 3 only) was never counted, so deleting
 * one must not double-subtract.
 */

export interface DeleteReviewHandlerInput {
  authUid: string | undefined;
  data: unknown;
}

export async function deleteReviewHandler(input: DeleteReviewHandlerInput): Promise<void> {
  if (!input.authUid) {
    throw errUnauthenticated();
  }
  const uid = input.authUid;
  const request = parseDeleteReviewRequest(input.data);
  const reviewId = reviewDocId(uid, request.productId);

  try {
    await db().runTransaction<void>(async (tx) => {
      const reviewRef = reviewDoc(reviewId);
      const reviewSnap = await tx.get(reviewRef);
      if (!reviewSnap.exists) return;

      const existing = reviewSnap.data() as Record<string, unknown>;
      if (existing.status === "published") {
        const statsRef = productStatsDoc(request.productId);
        const statsSnap = await tx.get(statsRef);
        const currentAggregate = ratingAggregateFromStatsData(statsSnap.data());
        const nextAggregate = applyRatingDelta(
          currentAggregate,
          existing.rating as number,
          -1,
        );
        tx.set(statsRef, statsFieldsFromAggregate(nextAggregate), { merge: true });
      }
      tx.delete(reviewRef);
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logUnexpected("deleteReview: unexpected failure", err, {
      uid,
      productId: request.productId,
    });
    throw errInternal();
  }
}

export const deleteReview = onCall(
  { region: FUNCTIONS_REGION, memory: "256MiB", timeoutSeconds: 30 },
  (request) => deleteReviewHandler({ authUid: request.auth?.uid, data: request.data }),
);
