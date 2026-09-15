import '../models/review_model.dart';
import '../models/review_moderation_action.dart';
import '../models/review_report_model.dart';

/// Admin-scoped Ratings/Reviews v1 data contract (Stage 8,
/// `24_RATINGS_REVIEWS_FEEDBACK_PLAN.md`).
///
/// Deliberately its own contract, separate from [ReviewsRepository] - the
/// customer-facing repository's own class doc comment (Stage 5) called this
/// out explicitly: `moderateReview` is admin-only and "belongs to the
/// dedicated Admin Reviews screen (Stage 8), which will get its own
/// admin-scoped repository, matching this codebase's established
/// customer/admin repository split" (e.g. `ProductDetailsRepository` vs. the
/// separate admin product-management data path).
///
/// Every method here reads/writes data ONLY an admin's Firestore rules allow
/// (`reviews`' `isAdmin()` clause reads ANY review regardless of status;
/// `reviewReports`' read rule is admin-only outright) - a non-admin caller
/// would see every read resolve to an empty result and every mutation fail
/// with a clean `ADMIN_REQUIRED` message, never a crash.
abstract class AdminReviewsRepository {
  /// Every review, across every product and status, newest first - bounded
  /// (see the real implementation's own limit), matching this app's
  /// established "single query, no composite index, in-memory filter/sort"
  /// convention (`FirestoreReviewsRepository.myReviews`,
  /// `isEligibleToReview`) rather than adding new composite indexes for a
  /// feature still local-only and at v1 volume. Never throws - `[]` on any
  /// read failure.
  Future<List<ReviewModel>> fetchReviews();

  /// Every report filed against [reviewId], newest first - the audit trail
  /// behind a flagged review's report count. Never throws - `[]` on any read
  /// failure or if the review has never been reported.
  Future<List<ReviewReportModel>> fetchReportsForReview(String reviewId);

  /// Hides, restores, or rejects [reviewId]. [reason] is REQUIRED for every
  /// [action] (v1 §0 decision 12 - "each action requires a reason", verified
  /// server-side by the `moderateReview` callable regardless of what this
  /// client sends). Returns `null` on success or a clean, `AppToast`-ready
  /// error message on failure.
  Future<String?> moderateReview({
    required String reviewId,
    required ReviewModerationAction action,
    required String reason,
  });
}
