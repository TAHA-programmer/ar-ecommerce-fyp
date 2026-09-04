import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/favorite_firestore_mapper.dart';

void main() {
  group('favorite_firestore_mapper', () {
    test('round-trips a real favorite through favoriteToFirestoreCreateMap/'
        'favoriteModelFromFirestore', () {
      final map = favoriteToFirestoreCreateMap();
      map['addedAt'] = Timestamp.fromDate(DateTime(2026, 2, 1));

      final restored = favoriteModelFromFirestore('product-123', map);

      expect(restored.productId, 'product-123');
      expect(restored.addedAt, DateTime(2026, 2, 1));
    });

    test('document ID is always the productId - never a separate field', () {
      final map = favoriteToFirestoreCreateMap();
      expect(map.containsKey('productId'), isFalse);
    });

    test('a missing/pending addedAt falls back safely rather than '
        'throwing', () {
      expect(() => favoriteModelFromFirestore('p1', const {}), returnsNormally);
      expect(
        () => favoriteModelFromFirestore('p1', const {'addedAt': null}),
        returnsNormally,
      );
      expect(
        () => favoriteModelFromFirestore('p1', const {'addedAt': 12345}),
        returnsNormally,
      );
    });
  });
}
