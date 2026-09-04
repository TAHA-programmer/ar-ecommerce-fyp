import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/category/commerce_category_model.dart';
import 'package:twin_ar/core/models/product/product_category.dart';

CommerceCategoryModel _model({
  String categoryId = 'furniture',
  String name = 'Furniture',
  bool isActive = true,
}) => CommerceCategoryModel(
  categoryId: categoryId,
  name: name,
  key: categoryId,
  kind: ProductCategory.furniture,
  imageUrl: '',
  isActive: isActive,
  sortOrder: 10,
);

void main() {
  group('CommerceCategoryModel', () {
    test('isSeeded is true for exactly the five seeded ids', () {
      for (final id in CommerceCategoryModel.seededCategoryIds) {
        expect(_model(categoryId: id).isSeeded, isTrue);
      }
      expect(_model(categoryId: 'outdoor-furniture').isSeeded, isFalse);
    });

    test('copyWith preserves categoryId/key/kind (immutable) and updates '
        'only the mutable fields', () {
      final original = _model();
      final updated = original.copyWith(
        name: 'Home Furniture',
        imageUrl: 'https://x.example/img.png',
        isActive: false,
        sortOrder: 40,
      );

      expect(updated.categoryId, original.categoryId);
      expect(updated.key, original.key);
      expect(updated.kind, original.kind);
      expect(updated.name, 'Home Furniture');
      expect(updated.imageUrl, 'https://x.example/img.png');
      expect(updated.isActive, isFalse);
      expect(updated.sortOrder, 40);
    });

    test('copyWith with no arguments returns identical values', () {
      final original = _model();
      final same = original.copyWith();
      expect(same.name, original.name);
      expect(same.imageUrl, original.imageUrl);
      expect(same.isActive, original.isActive);
      expect(same.sortOrder, original.sortOrder);
    });
  });
}
