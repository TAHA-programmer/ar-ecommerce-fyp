import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/product_rating_stats.dart';
import 'package:twin_ar/features/reviews/models/review_report_reason.dart';
import 'package:twin_ar/features/reviews/models/review_status.dart';
import 'package:twin_ar/features/reviews/repositories/review_firestore_mapper.dart';
import 'package:twin_ar/features/reviews/utils/review_author_display_name.dart';

void main() {
  group('reviewModelFromFirestore', () {
    test('maps a well-formed document', () {
      final createdAt = DateTime(2026, 1, 1, 10);
      final editedAt = DateTime(2026, 1, 15, 10);
      final review = reviewModelFromFirestore('u1_p1', {
        'productId': 'p1',
        'userId': 'u1',
        'authorDisplayName': 'Ayesha K.',
        'orderId': 'order-1',
        'rating': 4,
        'title': 'Great chair',
        'body': 'Really comfortable and sturdy.',
        'status': 'published',
        'reportCount': 2,
        'flaggedForReview': false,
        'createdAt': Timestamp.fromDate(createdAt),
        'editedAt': Timestamp.fromDate(editedAt),
        'moderatedAt': null,
        'moderatedBy': null,
        'moderationReason': null,
      });

      expect(review.id, 'u1_p1');
      expect(review.productId, 'p1');
      expect(review.userId, 'u1');
      expect(review.authorDisplayName, 'Ayesha K.');
      expect(review.orderId, 'order-1');
      expect(review.rating, 4);
      expect(review.title, 'Great chair');
      expect(review.body, 'Really comfortable and sturdy.');
      expect(review.status, ReviewStatus.published);
      expect(review.reportCount, 2);
      expect(review.flaggedForReview, false);
      expect(review.createdAt, createdAt);
      expect(review.editedAt, editedAt);
      expect(review.hasBeenEdited, true);
      expect(review.moderatedAt, isNull);
      expect(review.moderatedBy, isNull);
      expect(review.moderationReason, isNull);
    });

    test('an unrecognised status fails CLOSED to hidden, never published', () {
      final review = reviewModelFromFirestore('u1_p1', {
        'productId': 'p1',
        'userId': 'u1',
        'orderId': 'order-1',
        'rating': 5,
        'body': 'x',
        'status': 'not-a-real-status',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(review.status, ReviewStatus.hidden);
    });

    test('a missing status also fails CLOSED to hidden', () {
      final review = reviewModelFromFirestore('u1_p1', {
        'productId': 'p1',
        'userId': 'u1',
        'orderId': 'order-1',
        'rating': 5,
        'body': 'x',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(review.status, ReviewStatus.hidden);
    });

    test('an out-of-range rating is clamped, never crashes', () {
      final tooHigh = reviewModelFromFirestore('u1_p1', {
        'rating': 99,
        'body': 'x',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(tooHigh.rating, 5);

      final negative = reviewModelFromFirestore('u1_p1', {
        'rating': -3,
        'body': 'x',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(negative.rating, 0);
    });

    test('a missing/malformed rating defaults to 0, not a crash', () {
      final review = reviewModelFromFirestore('u1_p1', {
        'body': 'x',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(review.rating, 0);
    });

    test('a wrong-typed title is treated as absent, never thrown', () {
      final review = reviewModelFromFirestore('u1_p1', {
        'title': 12345,
        'body': 'x',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(review.title, isNull);
    });

    test('a missing createdAt falls back to now rather than throwing', () {
      final before = DateTime.now();
      final review = reviewModelFromFirestore('u1_p1', {
        'rating': 3,
        'body': 'x',
      });
      final after = DateTime.now();
      expect(
        review.createdAt.isAfter(before.subtract(const Duration(seconds: 1))),
        true,
      );
      expect(
        review.createdAt.isBefore(after.add(const Duration(seconds: 1))),
        true,
      );
    });

    test('a missing authorDisplayName falls back to the safe default - '
        'never blank, never the raw userId', () {
      final review = reviewModelFromFirestore('u1_p1', {
        'userId': 'u1',
        'rating': 4,
        'body': 'x',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(review.authorDisplayName, kFallbackReviewerDisplayName);
    });

    test('a wrong-typed authorDisplayName is treated as absent, falls back '
        'to the safe default', () {
      final review = reviewModelFromFirestore('u1_p1', {
        'authorDisplayName': 12345,
        'rating': 4,
        'body': 'x',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(review.authorDisplayName, kFallbackReviewerDisplayName);
    });
  });

  group('productRatingStatsFromFirestore', () {
    test('null data resolves to ProductRatingStats.zero', () {
      expect(productRatingStatsFromFirestore(null), ProductRatingStats.zero);
    });

    test('maps a well-formed productStats rating aggregate', () {
      final stats = productRatingStatsFromFirestore({
        'unitsSold':
            40, // unrelated existing field - must be ignored, not error
        'ratingSum': 18,
        'ratingCount': 4,
        'averageRating': 4.5,
        'rating1Count': 0,
        'rating2Count': 0,
        'rating3Count': 0,
        'rating4Count': 2,
        'rating5Count': 2,
      });
      expect(stats.ratingSum, 18);
      expect(stats.ratingCount, 4);
      expect(stats.averageRating, 4.5);
      expect(stats.rating4Count, 2);
      expect(stats.rating5Count, 2);
      expect(stats.hasReviews, true);
    });

    test('malformed/missing fields default to 0, never crash', () {
      final stats = productRatingStatsFromFirestore({
        'ratingSum': 'not-a-number',
      });
      expect(stats.ratingSum, 0);
      expect(stats.ratingCount, 0);
      expect(stats.averageRating, 0.0);
      expect(stats.rating1Count, 0);
      expect(stats.rating5Count, 0);
      expect(stats.hasReviews, false);
    });
  });

  group('reviewReportModelFromFirestore', () {
    test('maps a well-formed document', () {
      final createdAt = DateTime(2026, 2, 1, 9);
      final report = reviewReportModelFromFirestore('u2_u1_p1', {
        'reviewId': 'u1_p1',
        'reporterId': 'u2',
        'reason': 'spam',
        'note': 'Looks like a copy-pasted ad.',
        'createdAt': Timestamp.fromDate(createdAt),
      });

      expect(report.id, 'u2_u1_p1');
      expect(report.reviewId, 'u1_p1');
      expect(report.reporterId, 'u2');
      expect(report.reason, ReviewReportReason.spam);
      expect(report.note, 'Looks like a copy-pasted ad.');
      expect(report.createdAt, createdAt);
    });

    test('an unrecognised reason falls back to other, never crashes', () {
      final report = reviewReportModelFromFirestore('u2_u1_p1', {
        'reviewId': 'u1_p1',
        'reporterId': 'u2',
        'reason': 'not-a-real-reason',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(report.reason, ReviewReportReason.other);
    });

    test('a missing note maps to null, not an empty string', () {
      final report = reviewReportModelFromFirestore('u2_u1_p1', {
        'reviewId': 'u1_p1',
        'reporterId': 'u2',
        'reason': 'fake',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      expect(report.note, isNull);
    });
  });
}
