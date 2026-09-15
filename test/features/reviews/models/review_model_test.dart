import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/review_model.dart';
import 'package:twin_ar/features/reviews/models/review_status.dart';
import 'package:twin_ar/features/reviews/models/review_validation.dart';

void main() {
  group('ReviewModel.docIdFor', () {
    test('is deterministic per user+product - enforces one review per user '
        'per product even after repeat purchases', () {
      final a = ReviewModel.docIdFor(userId: 'u1', productId: 'p1');
      final b = ReviewModel.docIdFor(userId: 'u1', productId: 'p1');
      expect(a, b);
      expect(a, 'u1_p1');
    });

    test('differs for a different user or product', () {
      expect(
        ReviewModel.docIdFor(userId: 'u1', productId: 'p1'),
        isNot(ReviewModel.docIdFor(userId: 'u2', productId: 'p1')),
      );
      expect(
        ReviewModel.docIdFor(userId: 'u1', productId: 'p1'),
        isNot(ReviewModel.docIdFor(userId: 'u1', productId: 'p2')),
      );
    });
  });

  group('ReviewModel.isEditableAt / hasBeenEdited', () {
    ReviewModel review({required DateTime createdAt}) => ReviewModel(
      id: 'u1_p1',
      productId: 'p1',
      userId: 'u1',
      authorDisplayName: 'Test User',
      orderId: 'o1',
      rating: 5,
      body: 'Great product, exactly as described.',
      createdAt: createdAt,
    );

    test('editable immediately after creation', () {
      final createdAt = DateTime(2026, 1, 1);
      final r = review(createdAt: createdAt);
      expect(r.isEditableAt(createdAt), true);
      expect(r.hasBeenEdited, false);
    });

    test('editable exactly at the 30-day boundary', () {
      final createdAt = DateTime(2026, 1, 1);
      final r = review(createdAt: createdAt);
      final atBoundary = createdAt.add(
        const Duration(days: ReviewValidation.editWindowDays),
      );
      expect(r.isEditableAt(atBoundary), true);
    });

    test('not editable one moment past the 30-day boundary', () {
      final createdAt = DateTime(2026, 1, 1);
      final r = review(createdAt: createdAt);
      final pastBoundary = createdAt
          .add(const Duration(days: ReviewValidation.editWindowDays))
          .add(const Duration(seconds: 1));
      expect(r.isEditableAt(pastBoundary), false);
    });

    test('edit window is measured from the ORIGINAL createdAt, never reset '
        'by editedAt', () {
      final createdAt = DateTime(2026, 1, 1);
      final r = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Test User',
        orderId: 'o1',
        rating: 4,
        body: 'Updated my thoughts on this one after a week of use.',
        createdAt: createdAt,
        editedAt: createdAt.add(const Duration(days: 29)),
      );
      expect(r.hasBeenEdited, true);
      // 31 days after the ORIGINAL createdAt, even though editedAt was recent.
      expect(r.isEditableAt(createdAt.add(const Duration(days: 31))), false);
    });
  });

  group('ReviewStatusX.fromWire', () {
    test('parses known values', () {
      expect(ReviewStatusX.fromWire('published'), ReviewStatus.published);
      expect(ReviewStatusX.fromWire('hidden'), ReviewStatus.hidden);
      expect(ReviewStatusX.fromWire('rejected'), ReviewStatus.rejected);
    });

    test('unrecognised/corrupt data fails CLOSED to hidden, never '
        'published', () {
      expect(ReviewStatusX.fromWire('garbage'), ReviewStatus.hidden);
      expect(ReviewStatusX.fromWire(''), ReviewStatus.hidden);
    });

    test('only published reviews count toward the aggregate', () {
      expect(ReviewStatus.published.countsTowardAggregate, true);
      expect(ReviewStatus.hidden.countsTowardAggregate, false);
      expect(ReviewStatus.rejected.countsTowardAggregate, false);
    });
  });
}
