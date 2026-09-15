/** `reviews/{userId}_{productId}` - deterministic doc id. This is what
 *  enforces "one review per user per product, even after repeat purchases"
 *  (Ratings/Reviews v1 §0 decision 2) and turns a resubmission into an
 *  edit-in-place - exact mirror of the Flutter side's
 *  `ReviewModel.docIdFor`. */
export function reviewDocId(userId: string, productId: string): string {
  return `${userId}_${productId}`;
}

/** `reviewReports/{reporterId}_{reviewId}` - deterministic id enforcing one
 *  report per user per review (v1 §0 decision 10). Exact mirror of the
 *  Flutter side's `ReviewReportModel.docIdFor`. */
export function reviewReportDocId(reporterId: string, reviewId: string): string {
  return `${reporterId}_${reviewId}`;
}
