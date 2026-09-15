import * as functionsV1 from "firebase-functions/v1";
import * as logger from "firebase-functions/logger";

import { FUNCTIONS_REGION } from "./config";
import { db, productStatsDoc, reviewDoc, reviewsRef } from "./lib/firestore";
import {
  applyRatingDelta,
  ratingAggregateFromStatsData,
  statsFieldsFromAggregate,
} from "./lib/reviews/aggregate";

/**
 * `cleanupUserReviewsData` (Auth user-deletion trigger) - Ratings/Reviews v1
 * Stage 9, a SIBLING to `cleanupUserTryOnData` (same `auth.user().onDelete()`
 * event - Cloud Functions allows more than one function to listen for the
 * same Auth event, and both fire independently) rather than an extension of
 * it, since review cleanup is unrelated to Virtual Try-On data (matches that
 * function's own doc comment scoping it out).
 *
 * When a Firebase Auth account is deleted, this hard-deletes every
 * `reviews/{uid}_{productId}` document that user authored, regardless of
 * `status` (v1 §6's exact wording: "hard-delete that user's `reviews` docs
 * and reverse them out of `productStats`"). Each review is deleted inside
 * its own transaction that FIRST re-reads the review's CURRENT status
 * (never the possibly-stale status captured by the outer paginated query) -
 * mirrors `deleteReview.ts`'s exact transaction shape - and reverses its
 * rating out of `productStats/{productId}` ONLY if it was currently
 * `published` (a `hidden`/`rejected` review was never counted, so deleting
 * it must not double-subtract). Deleting an already-gone review (a prior
 * partial run, or a race with the customer's own `deleteReview` call before
 * their account finished deleting) is a harmless no-op, making the whole
 * sweep safely re-runnable.
 *
 * Deliberately OUT OF SCOPE for this stage (not silently missed - a
 * conscious boundary matching the tracker's exact Stage 9 wording, which
 * names only `reviews` + `productStats`): `reviewReports/{reporterId}_*`
 * documents where this user was the REPORTER are left in place. Those
 * carry a reason/note and the (now-deleted) user's uid, so a future stage
 * could reasonably extend this trigger to also purge them - flagged here
 * for that future decision, not fixed unasked.
 */

const REVIEW_PAGE_SIZE = 200;
const MAX_PAGES = 25; // 5,000 reviews - generous; logs a warning if exceeded

async function deleteReviewAndReverseAggregate(reviewId: string): Promise<void> {
  await db().runTransaction<void>(async (tx) => {
    const reviewRef = reviewDoc(reviewId);
    const reviewSnap = await tx.get(reviewRef);
    if (!reviewSnap.exists) return; // already gone - safe no-op

    const existing = reviewSnap.data() as Record<string, unknown>;
    if (existing.status === "published") {
      const productId = existing.productId as string;
      const statsRef = productStatsDoc(productId);
      const statsSnap = await tx.get(statsRef);
      const currentAggregate = ratingAggregateFromStatsData(statsSnap.data());
      const nextAggregate = applyRatingDelta(currentAggregate, existing.rating as number, -1);
      tx.set(statsRef, statsFieldsFromAggregate(nextAggregate), { merge: true });
    }
    tx.delete(reviewRef);
  });
}

export async function cleanupReviewsDataForUser(uid: string): Promise<void> {
  let pages = 0;
  for (;;) {
    pages += 1;
    const snap = await reviewsRef().where("userId", "==", uid).limit(REVIEW_PAGE_SIZE).get();
    if (snap.empty) break;

    // Safe to run in parallel: v1 §0 decision 2 (one review per user per
    // product, enforced by the deterministic `{uid}_{productId}` doc id)
    // guarantees this user's reviews never share a `productId`, so no two
    // of these transactions can ever touch the same `productStats` doc.
    await Promise.all(
      snap.docs.map((doc) =>
        deleteReviewAndReverseAggregate(doc.id).catch((err) =>
          logger.warn("cleanupUserReviewsData: could not delete a review", {
            uid,
            reviewId: doc.id,
            name: (err as { name?: unknown })?.name,
          }),
        ),
      ),
    );

    if (snap.size < REVIEW_PAGE_SIZE) break;
    if (pages >= MAX_PAGES) {
      logger.warn("cleanupUserReviewsData: reached the page cap - some reviews may remain", { uid });
      break;
    }
  }
}

export const cleanupUserReviewsData = functionsV1
  .region(FUNCTIONS_REGION)
  .auth.user()
  .onDelete(async (user) => {
    try {
      await cleanupReviewsDataForUser(user.uid);
      logger.info("cleanupUserReviewsData: cleanup complete", { uid: user.uid });
    } catch (err) {
      logger.error("cleanupUserReviewsData: cleanup failed", {
        uid: user.uid,
        name: (err as { name?: unknown })?.name,
      });
      throw err;
    }
  });
