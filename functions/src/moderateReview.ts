import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { FUNCTIONS_REGION, SUPER_ADMIN_ROLE } from "./config";
import { db, productStatsDoc, reviewDoc } from "./lib/firestore";
import {
  applyRatingDelta,
  ratingAggregateFromStatsData,
  statsFieldsFromAggregate,
} from "./lib/reviews/aggregate";
import {
  errAdminRequired,
  errInternal,
  errReviewNotFound,
  errUnauthenticated,
  logUnexpected,
} from "./lib/reviews/errors";
import {
  parseModerateReviewRequest,
  type ModerationAction,
} from "./lib/reviews/validation";

/**
 * `moderateReview` (callable) - Ratings/Reviews v1, Stage 3.
 *
 * Admin-only (`request.auth.token.role === SUPER_ADMIN_ROLE` - the exact
 * custom claim `firestore.rules`' `isAdmin()` already checks; no new
 * admin-detection mechanism invented). Transitions a review between
 * `published` / `hidden` / `rejected`. `reason` is REQUIRED for every
 * action, including `restore` (v1 §0 decision 12's exact wording: "each
 * action requires a reason") - always stamped onto `moderationReason`
 * alongside `moderatedAt`/`moderatedBy` for the audit trail.
 *
 * `productStats` reversal covers every from/to combination generically,
 * not just "hide reverses / restore re-applies": if the review WAS
 * `published` and the target is NOT, reverse (`-1`); if it was NOT
 * `published` and the target IS, apply (`+1`); if published-ness is
 * unchanged by the transition (hide → reject, or restoring an
 * already-published review), the aggregate is untouched - a review's
 * rating is counted at most once regardless of how many times an Admin
 * flips its status back and forth.
 *
 * Moderation only changes VISIBILITY - it never re-verifies the underlying
 * order or re-litigates purchase eligibility (that was already checked, by
 * `submitReview`, at the time the review was originally created).
 */

export interface ModerateReviewResult {
  status: "published" | "hidden" | "rejected";
}

export interface ModerateReviewHandlerInput {
  authUid: string | undefined;
  /** The caller's `role` custom claim, if any - production reads this from
   *  `request.auth.token.role`; tests inject it directly. */
  authRole: string | undefined;
  data: unknown;
}

function targetStatusFor(action: ModerationAction): "published" | "hidden" | "rejected" {
  switch (action) {
    case "hide":
      return "hidden";
    case "restore":
      return "published";
    case "reject":
      return "rejected";
  }
}

export async function moderateReviewHandler(
  input: ModerateReviewHandlerInput,
): Promise<ModerateReviewResult> {
  if (!input.authUid) {
    throw errUnauthenticated();
  }
  if (input.authRole !== SUPER_ADMIN_ROLE) {
    throw errAdminRequired();
  }
  const adminUid = input.authUid;
  const request = parseModerateReviewRequest(input.data);
  const targetStatus = targetStatusFor(request.action);

  try {
    return await db().runTransaction<ModerateReviewResult>(async (tx) => {
      const reviewRef = reviewDoc(request.reviewId);
      const reviewSnap = await tx.get(reviewRef);
      if (!reviewSnap.exists) {
        throw errReviewNotFound();
      }
      const review = reviewSnap.data() as Record<string, unknown>;

      const wasPublished = review.status === "published";
      const willBePublished = targetStatus === "published";

      if (wasPublished !== willBePublished) {
        const productId = review.productId as string;
        const statsRef = productStatsDoc(productId);
        const statsSnap = await tx.get(statsRef);
        const currentAggregate = ratingAggregateFromStatsData(statsSnap.data());
        const delta = willBePublished ? 1 : -1;
        const nextAggregate = applyRatingDelta(currentAggregate, review.rating as number, delta);
        tx.set(statsRef, statsFieldsFromAggregate(nextAggregate), { merge: true });
      }

      tx.update(reviewRef, {
        status: targetStatus,
        moderatedAt: FieldValue.serverTimestamp(),
        moderatedBy: adminUid,
        moderationReason: request.reason,
      });
      return { status: targetStatus };
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logUnexpected("moderateReview: unexpected failure", err, {
      adminUid,
      reviewId: request.reviewId,
      action: request.action,
    });
    throw errInternal();
  }
}

export const moderateReview = onCall(
  { region: FUNCTIONS_REGION, memory: "256MiB", timeoutSeconds: 30 },
  (request) =>
    moderateReviewHandler({
      authUid: request.auth?.uid,
      authRole: request.auth?.token?.role as string | undefined,
      data: request.data,
    }),
);
