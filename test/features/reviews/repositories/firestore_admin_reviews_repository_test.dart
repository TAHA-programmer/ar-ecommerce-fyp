import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/repositories/firestore_admin_reviews_repository.dart';

Future<void> _seedReview(
  FakeFirebaseFirestore firestore,
  String id, {
  required String productId,
  required String userId,
  required DateTime createdAt,
  String status = 'published',
  bool flaggedForReview = false,
  int reportCount = 0,
}) {
  return firestore.collection('reviews').doc(id).set({
    'productId': productId,
    'userId': userId,
    'authorDisplayName': 'Test User',
    'orderId': 'order-$userId-$productId',
    'rating': 4,
    'title': null,
    'body': 'A review body long enough to pass validation checks.',
    'status': status,
    'reportCount': reportCount,
    'flaggedForReview': flaggedForReview,
    'createdAt': Timestamp.fromDate(createdAt),
    'editedAt': null,
    'moderatedAt': null,
    'moderatedBy': null,
    'moderationReason': null,
  });
}

Future<void> _seedReport(
  FakeFirebaseFirestore firestore,
  String id, {
  required String reviewId,
  required String reporterId,
  required DateTime createdAt,
  String reason = 'spam',
  String? note,
}) {
  return firestore.collection('reviewReports').doc(id).set({
    'reviewId': reviewId,
    'reporterId': reporterId,
    'reason': reason,
    'note': note,
    'createdAt': Timestamp.fromDate(createdAt),
  });
}

void main() {
  group('FirestoreAdminReviewsRepository.fetchReviews', () {
    test('returns every review across every product and status, newest '
        'first', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedReview(
        firestore,
        'u1_p1',
        productId: 'p1',
        userId: 'u1',
        createdAt: DateTime(2026, 1, 1),
      );
      await _seedReview(
        firestore,
        'u2_p2',
        productId: 'p2',
        userId: 'u2',
        status: 'hidden',
        createdAt: DateTime(2026, 1, 3),
      );
      await _seedReview(
        firestore,
        'u3_p1',
        productId: 'p1',
        userId: 'u3',
        status: 'rejected',
        createdAt: DateTime(2026, 1, 2),
      );
      final repo = FirestoreAdminReviewsRepository(firestore: firestore);

      final reviews = await repo.fetchReviews();

      expect(reviews.map((r) => r.id).toList(), ['u2_p2', 'u3_p1', 'u1_p1']);
    });

    test('an empty collection returns an empty list, not an error', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreAdminReviewsRepository(firestore: firestore);
      expect(await repo.fetchReviews(), isEmpty);
    });
  });

  group('FirestoreAdminReviewsRepository.fetchReportsForReview', () {
    test('returns only reports filed against the requested review, newest '
        'first', () async {
      final firestore = FakeFirebaseFirestore();
      await _seedReport(
        firestore,
        'a_r1',
        reviewId: 'r1',
        reporterId: 'a',
        createdAt: DateTime(2026, 1, 1),
      );
      await _seedReport(
        firestore,
        'b_r1',
        reviewId: 'r1',
        reporterId: 'b',
        reason: 'fake',
        note: 'Reads like a bot-generated review.',
        createdAt: DateTime(2026, 1, 3),
      );
      await _seedReport(
        firestore,
        'c_r2',
        reviewId: 'r2',
        reporterId: 'c',
        createdAt: DateTime(2026, 1, 2),
      );
      final repo = FirestoreAdminReviewsRepository(firestore: firestore);

      final reports = await repo.fetchReportsForReview('r1');

      expect(reports.map((r) => r.id).toList(), ['b_r1', 'a_r1']);
      expect(reports.every((r) => r.reviewId == 'r1'), true);
    });

    test('a review with no reports returns an empty list', () async {
      final firestore = FakeFirebaseFirestore();
      final repo = FirestoreAdminReviewsRepository(firestore: firestore);
      expect(await repo.fetchReportsForReview('nothing-here'), isEmpty);
    });
  });
}
