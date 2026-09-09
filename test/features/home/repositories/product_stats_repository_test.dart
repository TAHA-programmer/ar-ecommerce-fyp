import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/home/repositories/firestore_product_stats_repository.dart';
import 'package:twin_ar/features/home/repositories/mock_product_stats_repository.dart';

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
    });
  });
}
