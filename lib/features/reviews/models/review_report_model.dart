import 'review_report_reason.dart';

/// A single report against a review (`reviewReports/{reporterId}_{reviewId}`
/// - Ratings/Reviews v1). The deterministic id enforces "one report per user
/// per review" (v1 §0 decision 10): a repeat report from the same reporter
/// overwrites this same document rather than creating a second one, so
/// `reviews/{id}.reportCount` (a UNIQUE-reporter count) can never be
/// inflated by one person reporting the same review twice.
///
/// Admin-only: `firestore.rules` allows reading this collection to
/// `isAdmin()` alone - a reporter never sees their own report reflected
/// back, and a review's author never sees who reported it.
class ReviewReportModel {
  /// `{reporterId}_{reviewId}`.
  final String id;

  final String reviewId;
  final String reporterId;
  final ReviewReportReason reason;
  final String? note;
  final DateTime createdAt;

  const ReviewReportModel({
    required this.id,
    required this.reviewId,
    required this.reporterId,
    required this.reason,
    this.note,
    required this.createdAt,
  });

  static String docIdFor({
    required String reporterId,
    required String reviewId,
  }) => '${reporterId}_$reviewId';
}
