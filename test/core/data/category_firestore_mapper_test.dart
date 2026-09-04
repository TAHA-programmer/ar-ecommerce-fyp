import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/category_firestore_mapper.dart';
import 'package:twin_ar/core/models/category/commerce_category_model.dart';
import 'package:twin_ar/core/models/product/product_category.dart';

void main() {
  group('category_firestore_mapper', () {
    test(
      'round-trips a real category through toFirestoreMap/fromFirestore',
      () {
        const model = CommerceCategoryModel(
          categoryId: 'furniture',
          name: 'Furniture',
          key: 'furniture',
          kind: ProductCategory.furniture,
          imageUrl: 'https://x.example/img.png',
          isActive: true,
          sortOrder: 10,
        );

        final map = model.toFirestoreMap();
        final restored = categoryModelFromFirestore('furniture', map);

        expect(restored.categoryId, model.categoryId);
        expect(restored.name, model.name);
        expect(restored.key, model.key);
        expect(restored.kind, model.kind);
        expect(restored.imageUrl, model.imageUrl);
        expect(restored.isActive, model.isActive);
        expect(restored.sortOrder, model.sortOrder);
      },
    );

    test('never writes ProductCategory.all as kind - toFirestoreMap on '
        'every real kind value stays inside the closed 5-value set', () {
      for (final kind in ProductCategory.values) {
        if (kind == ProductCategory.all) continue;
        final model = CommerceCategoryModel(
          categoryId: kind.name,
          name: kind.name,
          key: kind.name,
          kind: kind,
          imageUrl: '',
          isActive: true,
          sortOrder: 10,
        );
        expect(model.toFirestoreMap()['kind'], kind.name);
      }
    });

    test('an unknown/missing kind string falls back to a real category, '
        'never to the .all sentinel', () {
      final fromMissing = categoryModelFromFirestore('x', {
        'name': 'X',
        'key': 'x',
        'imageUrl': '',
        'isActive': true,
        'sortOrder': 0,
      });
      expect(fromMissing.kind, isNot(ProductCategory.all));

      final fromGarbage = categoryModelFromFirestore('x', {
        'name': 'X',
        'key': 'x',
        'kind': 'not-a-real-kind',
        'imageUrl': '',
        'isActive': true,
        'sortOrder': 0,
      });
      expect(fromGarbage.kind, isNot(ProductCategory.all));
    });

    test('a field present with the WRONG type (not merely missing) throws - '
        'this is the exact failure `FirestoreCategoryRepository`\'s snapshot '
        'listener must catch to avoid crashing on malformed real-world '
        'data; see that class\'s `_onSnapshot`', () {
      expect(
        () => categoryModelFromFirestore('x', const {
          'name': 12345, // a number, not a String - `as String?` throws
          'key': 'x',
          'kind': 'furniture',
          'imageUrl': '',
          'isActive': true,
          'sortOrder': 0,
        }),
        throwsA(isA<TypeError>()),
      );
    });

    test('missing/malformed fields fall back to safe defaults rather than '
        'throwing', () {
      final restored = categoryModelFromFirestore('some-id', const {});
      expect(restored.categoryId, 'some-id');
      expect(restored.name, '');
      expect(restored.key, 'some-id'); // falls back to the document id
      expect(restored.imageUrl, '');
      expect(restored.isActive, isTrue); // defaults to visible, not hidden
      expect(restored.sortOrder, 0);
    });

    test('sortOrder tolerates a Firestore int-typed number', () {
      final restored = categoryModelFromFirestore('x', {
        'name': 'X',
        'key': 'x',
        'kind': 'furniture',
        'imageUrl': '',
        'isActive': true,
        'sortOrder': 10, // Dart int, not double - num? cast must handle both
      });
      expect(restored.sortOrder, 10);
    });
  });
}
