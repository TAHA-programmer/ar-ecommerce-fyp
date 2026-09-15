import { FieldValue } from "firebase-admin/firestore";
import { HttpsError, onCall } from "firebase-functions/v2/https";

import { FUNCTIONS_REGION, REVIEW_REPORT_FLAG_THRESHOLD } from "./config";
import { db, reviewDoc, reviewReportDoc } from "./lib/firestore";
import {
  errCannotReportOwnReview,
  errInternal,
  errReviewNotFound,
  errUnauthenticated,
  logUnexpected,
} from "./lib/reviews/errors";
import { reviewReportDocId } from "./lib/reviews/model";
import { parseReportReviewRequest } from "./lib/reviews/validation";

/**
 * `reportReview` (callable) - Ratings/Reviews v1, Stage 3.
 *
 * Records the caller's report against a review. The deterministic
 * `reviewReports/{reporterId}_{reviewId}` doc id (see
 * `lib/reviews/model.ts#reviewReportDocId`) is what enforces "one report
 * per user per review" (v1 §0 decision 10): a repeat report from the SAME
 * reporter is a harmless idempotent no-op - it can never inflate
 * `reviews/{id}.reportCount` a second time, because the transaction checks
 * whether that exact report document already exists before incrementing
 * anything.
 *
 * `reportCount` reaching `REVIEW_REPORT_FLAG_THRESHOLD` sets
 * `flaggedForReview = true` - an Admin-queue PRIORITY signal only. Nothing
 * here ever changes `status` or touches `productStats`: a reported review
 * is NEVER auto-hidden (v1 §0 decision 11) - manual moderation
 * (`moderateReview`, below) stays the only thing that can change visibility
 * or the rating aggregate.
 *
 * A caller cannot report their own review (defence in depth - the customer
 * UI already hides the report affordance on a user's own review card, but
 * the server re-checks it independently, matching this codebase's
 * established pattern of never trusting a client-side-only restriction).
 */

export interface ReportReviewResult {
  /** `false` when this exact (reporter, review) pair had already reported -
   *  a harmless no-op, not an error. */
  reported: boolean;
}

export interface ReportReviewHandlerInput {
  authUid: string | undefined;
  data: unknown;
}

export async function reportReviewHandler(
  input: ReportReviewHandlerInput,
): Promise<ReportReviewResult> {
  if (!input.authUid) {
    throw errUnauthenticated();
  }
  const uid = input.authUid;
  const request = parseReportReviewRequest(input.data);

  try {
    return await db().runTransaction<ReportReviewResult>(async (tx) => {
      const reviewRef = reviewDoc(request.reviewId);
      const reportRef = reviewReportDoc(reviewReportDocId(uid, request.reviewId));
      const [reviewSnap, reportSnap] = await Promise.all([tx.get(reviewRef), tx.get(reportRef)]);

      if (!reviewSnap.exists) {
        throw errReviewNotFound();
      }
      const review = reviewSnap.data() as Record<string, unknown>;
      if (review.userId === uid) {
        throw errCannotReportOwnReview();
      }

      if (reportSnap.exists) {
        // This exact reporter already reported this exact review - one
        // report per user per review (v1 §0 decision 10). Not an error.
        return { reported: false };
      }

      const currentCount = typeof review.reportCount === "number" ? review.reportCount : 0;
      const newCount = currentCount + 1;

      tx.create(reportRef, {
        reviewId: request.reviewId,
        reporterId: uid,
        reason: request.reason,
        note: request.note,
        createdAt: FieldValue.serverTimestamp(),
      });
      tx.update(reviewRef, {
        reportCount: newCount,
        flaggedForReview:
          newCount >= REVIEW_REPORT_FLAG_THRESHOLD || Boolean(review.flaggedForReview),
      });
      return { reported: true };
    });
  } catch (err) {
    if (err instanceof HttpsError) throw err;
    logUnexpected("reportReview: unexpected failure", err, {
      uid,
      reviewId: request.reviewId,
    });
    throw errInternal();
  }
}

export const reportReview = onCall(
  { region: FUNCTIONS_REGION, memory: "256MiB", timeoutSeconds: 30 },
  (request) => reportReviewHandler({ authUid: request.auth?.uid, data: request.data }),
);
