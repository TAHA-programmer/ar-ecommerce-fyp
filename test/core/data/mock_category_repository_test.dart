import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/models/product/product_category.dart';

void main() {
  group('MockCategoryRepository', () {
    late MockCategoryRepository repo;

    setUp(() {
      repo = MockCategoryRepository();
    });

    test('starts pre-seeded with the five canonical categories, loaded '
        'synchronously (isLoading false immediately)', () {
      expect(repo.isLoading, isFalse);
      expect(repo.hasError, isFalse);
      expect(repo.categories.length, 5);
      expect(repo.categories.map((c) => c.categoryId).toSet(), {
        'furniture',
        'clothing',
        'rugs',
        'decor',
        'lighting',
      });
    });

    test('categories are sorted by sortOrder', () {
      final sortOrders = repo.categories.map((c) => c.sortOrder).toList();
      final sorted = List.of(sortOrders)..sort();
      expect(sortOrders, sorted);
    });

    test(
      'addCategory slugifies the name into a stable key/categoryId',
      () async {
        final created = await repo.addCategory(
          name: 'Outdoor Furniture',
          kind: ProductCategory.furniture,
        );
        expect(created.categoryId, 'outdoor-furniture');
        expect(created.key, 'outdoor-furniture');
        expect(repo.categories.length, 6);
      },
    );

    test('addCategory assigns sortOrder as max+10', () async {
      final maxBefore = repo.categories
          .map((c) => c.sortOrder)
          .reduce((a, b) => a > b ? a : b);
      final created = await repo.addCategory(
        name: 'New One',
        kind: ProductCategory.decor,
      );
      expect(created.sortOrder, maxBefore + 10);
    });

    test('addCategory rejects an exact key collision', () async {
      expect(
        () => repo.addCategory(
          name: 'furniture',
          kind: ProductCategory.furniture,
        ),
        throwsA(isA<StateError>()),
      );
    });

    test('addCategory rejects a name that slugifies to empty ("!!!") '
        'without creating any category', () async {
      expect(
        () => repo.addCategory(name: '!!!', kind: ProductCategory.furniture),
        throwsA(isA<StateError>()),
      );
      expect(repo.categories.length, 5); // unchanged
    });

    test('addCategory rejects whitespace-only names without creating any '
        'category', () async {
      expect(
        () => repo.addCategory(name: '   ', kind: ProductCategory.decor),
        throwsA(isA<StateError>()),
      );
      expect(repo.categories.length, 5);
    });

    test('addCategory rejects ProductCategory.all without creating any '
        'category', () async {
      expect(
        () => repo.addCategory(name: 'Everything', kind: ProductCategory.all),
        throwsA(isA<StateError>()),
      );
      expect(repo.categories.length, 5);
      expect(repo.categories.any((c) => c.categoryId == 'everything'), isFalse);
    });

    test('addCategory rejects a name over 60 characters without creating '
        'any category', () async {
      final longName = 'x' * 61;
      expect(
        () => repo.addCategory(name: longName, kind: ProductCategory.decor),
        throwsA(isA<StateError>()),
      );
      expect(repo.categories.length, 5);
    });

    test('addCategory notifies listeners', () async {
      var notified = false;
      repo.addListener(() => notified = true);
      await repo.addCategory(name: 'New One', kind: ProductCategory.decor);
      expect(notified, isTrue);
    });

    test(
      'updateCategory changes only name/imageUrl/isActive/sortOrder',
      () async {
        final original = repo.categories.firstWhere(
          (c) => c.categoryId == 'furniture',
        );
        await repo.updateCategory(
          original.copyWith(name: 'Home Furniture', isActive: false),
        );
        final updated = repo.categories.firstWhere(
          (c) => c.categoryId == 'furniture',
        );
        expect(updated.name, 'Home Furniture');
        expect(updated.isActive, isFalse);
        expect(updated.key, 'furniture');
        expect(updated.kind, ProductCategory.furniture);
      },
    );

    test('deleteCategory refuses every one of the five seeded ids', () async {
      for (final id in ['furniture', 'clothing', 'rugs', 'decor', 'lighting']) {
        expect(
          () => repo.deleteCategory(id),
          throwsA(isA<StateError>()),
          reason: '$id must be permanently protected',
        );
      }
      expect(repo.categories.length, 5); // nothing was actually removed
    });

    test('deleteCategory removes a custom category', () async {
      final created = await repo.addCategory(
        name: 'Outdoor Furniture',
        kind: ProductCategory.furniture,
      );
      await repo.deleteCategory(created.categoryId);
      expect(
        repo.categories.any((c) => c.categoryId == created.categoryId),
        isFalse,
      );
    });

    test(
      'failure-injection hooks throw exactly the configured error',
      () async {
        repo.failAddCategoryWith = StateError('boom-add');
        expect(
          () => repo.addCategory(name: 'X', kind: ProductCategory.decor),
          throwsA(isA<StateError>()),
        );

        repo.failUpdateCategoryWith = StateError('boom-update');
        final furniture = repo.categories.firstWhere(
          (c) => c.categoryId == 'furniture',
        );
        expect(
          () => repo.updateCategory(furniture),
          throwsA(isA<StateError>()),
        );

        repo.failDeleteCategoryWith = StateError('boom-delete');
        final custom = await MockCategoryRepository().addCategory(
          name: 'Custom',
          kind: ProductCategory.decor,
        );
        repo.debugSetCategories([...repo.categories, custom]);
        expect(
          () => repo.deleteCategory(custom.categoryId),
          throwsA(isA<StateError>()),
        );
      },
    );

    test('simulateLoading/simulateError/simulateRecovery drive the '
        'loading/error surface used by the Admin UI', () {
      repo.simulateLoading();
      expect(repo.isLoading, isTrue);

      repo.simulateError();
      expect(repo.isLoading, isFalse);
      expect(repo.hasError, isTrue);

      repo.simulateRecovery(repo.categories);
      expect(repo.isLoading, isFalse);
      expect(repo.hasError, isFalse);
    });
  });
}
