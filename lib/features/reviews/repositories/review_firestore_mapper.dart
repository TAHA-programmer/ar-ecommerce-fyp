import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/product_rating_stats.dart';
import '../models/review_model.dart';
import '../models/review_report_model.dart';
import '../models/review_report_reason.dart';
import '../models/review_status.dart';
import '../utils/review_author_display_name.dart';

// Firestore <-> reviews-feature model mapping (Ratings/Reviews v1,
// `24_RATINGS_REVIEWS_FEEDBACK_PLAN.md`). Deliberately its own file, kept
// pure (no `cloud_firestore` I/O, only the `Map`/`Timestamp` shapes it reads
// back), mirroring `order_firestore_mapper.dart`'s standalone convention -
// both so it stays independently unit-testable and so a mapping bug can
// never masquerade as a Firestore-connectivity bug.
//
// Every field uses an explicit `is T` check, never an unsafe `as T?` cast -
// same reasoning as `order_firestore_mapper.dart`: a client never writes
// these documents directly (`firestore.rules` denies it), but a read must
// still never crash on a stray malformed/legacy field.

String _str(dynamic v, [String fallback = '']) => v is String ? v : fallback;

int _intOr(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

double _numOr(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

String? _strOrNull(dynamic v) => v is String ? v : null;

DateTime? _dateOrNull(dynamic v) => v is Timestamp ? v.toDate() : null;

/// A missing/pending `createdAt` reads as "now" (display-only
/// approximation) - mirrors `order_firestore_mapper.dart`'s
/// `_dateFromTimestamp`. In practice `createdAt` is always
/// `Timestamp.fromMillis(...)`-written by `submitReview` (never a
/// `serverTimestamp()` sentinel - see the Stage 2 tracker note on why), so
/// this fallback is defensive only.
DateTime _dateOr(dynamic v, [DateTime? fallback]) =>
    _dateOrNull(v) ?? fallback ?? DateTime.now();

/// Read direction: a `reviews/{id}` Firestore document -> [ReviewModel].
/// Unrecognised/corrupt `status` fails CLOSED to [ReviewStatus.hidden] via
/// [ReviewStatusX.fromWire] - never silently shown as published.
ReviewModel reviewModelFromFirestore(String id, Map<String, dynamic> data) {
  return ReviewModel(
    id: id,
    productId: _str(data['productId']),
    userId: _str(data['userId']),
    // A missing/malformed field (should never happen for a server-written
    // doc, but the mapper is defensive regardless - see this file's header)
    // falls back to the same safe default the server itself uses when a
    // profile lookup fails - never a blank name, never raw account data.
    authorDisplayName: _str(
      data['authorDisplayName'],
      kFallbackReviewerDisplayName,
    ),
    orderId: _str(data['orderId']),
    rating: _intOr(data['rating']).clamp(0, 5).toInt(),
    title: _strOrNull(data['title']),
    body: _str(data['body']),
    status: ReviewStatusX.fromWire(_str(data['status'], 'hidden')),
    reportCount: _intOr(data['reportCount']),
    flaggedForReview: data['flaggedForReview'] == true,
    createdAt: _dateOr(data['createdAt']),
    editedAt: _dateOrNull(data['editedAt']),
    moderatedAt: _dateOrNull(data['moderatedAt']),
    moderatedBy: _strOrNull(data['moderatedBy']),
    moderationReason: _strOrNull(data['moderationReason']),
  );
}

/// Read direction: a `productStats/{productId}` document's rating fields ->
/// [ProductRatingStats]. `data == null` (no document / product never
/// reviewed) and any malformed field both resolve to [ProductRatingStats.zero]
/// - the honest empty state, matching every other field on this
/// already-established document (v1 §0 decision 16).
ProductRatingStats productRatingStatsFromFirestore(Map<String, dynamic>? data) {
  if (data == null) return ProductRatingStats.zero;
  return ProductRatingStats(
    ratingSum: _intOr(data['ratingSum']),
    ratingCount: _intOr(data['ratingCount']),
    averageRating: _numOr(data['averageRating']),
    rating1Count: _intOr(data['rating1Count']),
    rating2Count: _intOr(data['rating2Count']),
    rating3Count: _intOr(data['rating3Count']),
    rating4Count: _intOr(data['rating4Count']),
    rating5Count: _intOr(data['rating5Count']),
  );
}

/// Read direction: a `reviewReports/{id}` Firestore document ->
/// [ReviewReportModel] - Admin-only (`firestore.rules`' `reviewReports`
/// read rule), Stage 8's audit view of who reported a review and why.
/// Unrecognised/corrupt `reason` falls back to [ReviewReportReason.other]
/// via [ReviewReportReasonX.fromWire] - never crashes the audit view.
ReviewReportModel reviewReportModelFromFirestore(
  String id,
  Map<String, dynamic> data,
) {
  return ReviewReportModel(
    id: id,
    reviewId: _str(data['reviewId']),
    reporterId: _str(data['reporterId']),
    reason: ReviewReportReasonX.fromWire(_str(data['reason'], 'other')),
    note: _strOrNull(data['note']),
    createdAt: _dateOr(data['createdAt']),
  );
}
