import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/home/repositories/firestore_product_stats_repository.dart';
import 'package:twin_ar/features/home/repositories/mock_product_stats_repository.dart';
import 'package:twin_ar/features/reviews/models/product_rating_stats.dart';

void main() {
  group('FirestoreProductStatsRepository', () {
    test(
      'ranks by unitsSold desc, drops a zero value, respects limit',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('productStats').doc('a').set({
          'unitsSold': 5,
          'favoriteCount': 1,
        });
        await firestore.collection('productStats').doc('b').set({
          'unitsSold': 40,
          'favoriteCount': 2,
        });
        await firestore.collection('productStats').doc('c').set({
          'unitsSold':
              0, // a cold doc (favourite added then removed) — not real
          'favoriteCount': 9,
        });
        final repo = FirestoreProductStatsRepository(firestore: firestore);

        final sold = await repo.topByUnitsSold(limit: 10);
        expect(sold.map((r) => r.productId).toList(), ['b', 'a']);
        expect(sold.first.value, 40);

        final fav = await repo.topByFavoriteCount(limit: 2);
        expect(fav.map((r) => r.productId).toList(), ['c', 'b']);
      },
    );

    test('an empty collection returns an empty list, never an error', () async {
      final repo = FirestoreProductStatsRepository(
        firestore: FakeFirebaseFirestore(),
      );
      expect(await repo.topByUnitsSold(), isEmpty);
      expect(await repo.topByFavoriteCount(), isEmpty);
    });

    group('ratingStatsFor (Ratings/Reviews v1 Stage 12)', () {
      test(
        'reads the rating aggregate for exactly the requested ids',
        () async {
          final firestore = FakeFirebaseFirestore();
          await firestore.collection('productStats').doc('a').set({
            'unitsSold': 5,
            'ratingSum': 18,
            'ratingCount': 4,
            'averageRating': 4.5,
            'rating4Count': 2,
            'rating5Count': 2,
          });
          await firestore.collection('productStats').doc('b').set({
            'ratingSum': 3,
            'ratingCount': 1,
            'averageRating': 3.0,
            'rating3Count': 1,
          });
          // Never requested - must never appear in the result even though it
          // exists in the collection.
          await firestore.collection('productStats').doc('c').set({
            'ratingSum': 5,
            'ratingCount': 1,
            'averageRating': 5.0,
            'rating5Count': 1,
          });
          final repo = FirestoreProductStatsRepository(firestore: firestore);

          final result = await repo.ratingStatsFor(['a', 'b']);

          expect(result.keys.toSet(), {'a', 'b'});
          expect(result['a']!.averageRating, 4.5);
          expect(result['a']!.ratingCount, 4);
          expect(result['b']!.averageRating, 3.0);
        },
      );

      test('an id with no productStats doc is simply absent from the '
          'result - never a fabricated zero entry', () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('productStats').doc('a').set({
          'ratingSum': 5,
          'ratingCount': 1,
          'averageRating': 5.0,
        });
        final repo = FirestoreProductStatsRepository(firestore: firestore);

        final result = await repo.ratingStatsFor(['a', 'never-reviewed']);

        expect(result.containsKey('a'), true);
        expect(result.containsKey('never-reviewed'), false);
      });

      test(
        'an empty id list resolves to an empty map without querying',
        () async {
          final repo = FirestoreProductStatsRepository(
            firestore: FakeFirebaseFirestore(),
          );
          expect(await repo.ratingStatsFor([]), isEmpty);
        },
      );
    });
  });

  group('MockProductStatsRepository', () {
    test(
      'mirrors the contract: value>0 only, desc, id tie-break, limit',
      () async {
        final repo = MockProductStatsRepository(
          unitsSold: {'z': 3, 'a': 3, 'm': 10, 'zero': 0},
        );
        final ranked = await repo.topByUnitsSold(limit: 2);
        expect(ranked.map((r) => r.productId).toList(), ['m', 'a']);
      },
    );

    test('throwOnRead simulates a read blowing up inside the boundary', () {
      final repo = MockProductStatsRepository(throwOnRead: true);
      expect(repo.topByUnitsSold(), throwsStateError);
      expect(repo.topByFavoriteCount(), throwsStateError);
      expect(repo.ratingStatsFor(['a']), throwsStateError);
    });

    group('ratingStatsFor (Ratings/Reviews v1 Stage 12)', () {
      const statsA = ProductRatingStats(
        ratingSum: 18,
        ratingCount: 4,
        averageRating: 4.5,
        rating1Count: 0,
        rating2Count: 0,
        rating3Count: 0,
        rating4Count: 2,
        rating5Count: 2,
      );

      test('returns only the requested ids that were seeded', () async {
        final repo = MockProductStatsRepository(ratingStats: {'a': statsA});
        final result = await repo.ratingStatsFor(['a', 'never-seeded']);
        expect(result.keys.toSet(), {'a'});
        expect(result['a'], statsA);
      });

      test('an empty seeded map means every id is absent', () async {
        final repo = MockProductStatsRepository();
        expect(await repo.ratingStatsFor(['a', 'b']), isEmpty);
      });
    });
  });
}
