import '../models/review_model.dart';
import '../models/review_moderation_action.dart';
import '../models/review_report_model.dart';
import 'admin_reviews_repository.dart';

/// In-memory [AdminReviewsRepository] - a test double AND a faithful
/// reference implementation of the Stage 8 admin business rules (every
/// review of every status is visible, `moderateReview` stamps
/// `moderatedAt`/`moderatedBy`/`moderationReason` on every call), mirroring
/// [MockReviewsRepository]'s established dual role for the customer side.
class MockAdminReviewsRepository implements AdminReviewsRepository {
  /// The uid stamped as `moderatedBy` on a successful [moderateReview] call -
  /// mirrors what the real callable reads from `request.auth.uid`.
  String adminUid;

  /// Injectable clock, matching [MockReviewsRepository]'s convention.
  DateTime Function() now;

  final Map<String, ReviewModel> _reviewsById = {};
  final Map<String, List<ReviewReportModel>> _reportsByReviewId = {};

  /// Test setup: the next [moderateReview] call returns this error instead
  /// of mutating anything - simulates a server-side rejection (e.g. a blank
  /// reason, or the reviewer having since deleted the review).
  String? nextModerateError;

  MockAdminReviewsRepository({
    this.adminUid = 'mock-admin',
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  /// Test setup: adds/replaces [review] in the in-memory store.
  void seedReview(ReviewModel review) {
    _reviewsById[review.id] = review;
  }

  /// Test setup: adds [report] against its own `reviewId`.
  void seedReport(ReviewReportModel report) {
    (_reportsByReviewId[report.reviewId] ??= []).add(report);
  }

  @override
  Future<List<ReviewModel>> fetchReviews() async {
    final all = _reviewsById.values.toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return all;
  }

  @override
  Future<List<ReviewReportModel>> fetchReportsForReview(String reviewId) async {
    final reports = List<ReviewReportModel>.from(
      _reportsByReviewId[reviewId] ?? const [],
    )..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return reports;
  }

  @override
  Future<String?> moderateReview({
    required String reviewId,
    required ReviewModerationAction action,
    required String reason,
  }) async {
    if (nextModerateError != null) {
      final error = nextModerateError;
      nextModerateError = null;
      return error;
    }
    final review = _reviewsById[reviewId];
    if (review == null) return 'This review no longer exists.';
    if (reason.trim().isEmpty) {
      return 'A reason is required for every moderation action.';
    }

    _reviewsById[reviewId] = review.copyWith(
      status: action.targetStatus,
      moderatedAt: now(),
      moderatedBy: adminUid,
      moderationReason: reason.trim(),
    );
    return null;
  }
}
