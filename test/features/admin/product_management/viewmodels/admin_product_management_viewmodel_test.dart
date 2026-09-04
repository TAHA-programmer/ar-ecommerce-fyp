import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/category/commerce_category_model.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/admin/product_management/models/admin_category_config.dart';
import 'package:twin_ar/features/admin/product_management/models/admin_category_sort_option.dart';
import 'package:twin_ar/features/admin/product_management/models/admin_product_sort_option.dart';
import 'package:twin_ar/features/admin/product_management/viewmodels/admin_product_management_viewmodel.dart';

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

/// Lets `AppToast.error`/`AppToast.success`'s internal auto-dismiss timer
/// finish before the test tears down its widget tree - mirrors the existing
/// Phase 8.6 error-path test's own pump sequence below.
Future<void> _settleToast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 350));
}

void main() {
  late MockCommerceDatabase mockDatabase;
  late MockCategoryRepository mockCategoryRepository;
  late MockStorageService mockStorageService;
  late AdminProductManagementViewModel viewModel;

  setUp(() {
    mockDatabase = MockCommerceDatabase();
    mockCategoryRepository = MockCategoryRepository();
    mockStorageService = MockStorageService();
    viewModel = AdminProductManagementViewModel(
      mockDatabase,
      mockCategoryRepository,
      storageService: mockStorageService,
    );
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('AdminProductManagementViewModel - Products Mode', () {
    test('initial state has all products and default filters', () {
      expect(viewModel.filteredProducts.length, mockDatabase.products.length);
      expect(viewModel.totalProductsCount, mockDatabase.products.length);
      expect(viewModel.searchQuery, '');
      expect(viewModel.filterState.hasActiveFilters, false);
      expect(viewModel.sortOption, AdminProductSortOption.newest);
    });

    test('search filters by name, category, or sku', () {
      final initialCount = viewModel.filteredProducts.length;

      viewModel.setSearchQuery('sofa');
      final sofaCount = viewModel.filteredProducts.length;
      expect(sofaCount, lessThan(initialCount));
      expect(sofaCount, greaterThan(0));
    });

    testWidgets('delete product removes it and updates list', (tester) async {
      final context = await _pumpContext(tester);
      final initialLength = viewModel.filteredProducts.length;
      final productToDelete = viewModel.filteredProducts.first;

      final result = await viewModel.deleteProduct(context, productToDelete.id);

      expect(result, isTrue);
      expect(viewModel.filteredProducts.length, initialLength - 1);
      expect(viewModel.filteredProducts.contains(productToDelete), isFalse);
    });

    testWidgets('delete product catches a database failure and returns false '
        'instead of throwing (Phase 8.6)', (tester) async {
      final context = await _pumpContext(tester);
      final throwingDatabase = _ThrowingDeleteDatabase();
      final throwingViewModel = AdminProductManagementViewModel(
        throwingDatabase,
        MockCategoryRepository(),
      );
      addTearDown(throwingViewModel.dispose);
      final productId = throwingDatabase.products.first.id;

      final result = await throwingViewModel.deleteProduct(context, productId);

      expect(result, isFalse);
      await _settleToast(tester);
    });

    testWidgets('R16: deleting a product with a Room-AR model also deletes its '
        'GLB from Storage', (tester) async {
      final context = await _pumpContext(tester);
      final chair = mockDatabase.getProductById('luna-accent-chair');
      expect(chair.arMetadata, isNotNull);

      final result = await viewModel.deleteProduct(context, chair.id);

      expect(result, isTrue);
      expect(
        mockStorageService.deletedArModelPaths,
        contains(chair.arMetadata!.storagePath),
      );
      expect(viewModel.filteredProducts.any((p) => p.id == chair.id), isFalse);
    });

    testWidgets('R16: deleting a product whose GLB cleanup FAILS still deletes '
        'the product and warns', (tester) async {
      final context = await _pumpContext(tester);
      mockStorageService.failDeleteArModel = true;
      final chair = mockDatabase.getProductById('luna-accent-chair');

      final result = await viewModel.deleteProduct(context, chair.id);

      expect(result, isTrue); // the Firestore delete is authoritative
      expect(viewModel.filteredProducts.any((p) => p.id == chair.id), isFalse);
      expect(
        mockStorageService.deletedArModelPaths,
        contains(chair.arMetadata!.storagePath),
      ); // attempted
      expect(viewModel.arModelCleanupWarning, isNotNull);
      expect(viewModel.arModelCleanupWarning, contains('manual cleanup'));
      await _settleToast(tester);
    });

    testWidgets('R16: deleting a product with no Room-AR model touches no '
        'Storage', (tester) async {
      final context = await _pumpContext(tester);
      final plain = viewModel.filteredProducts.firstWhere(
        (p) => p.arMetadata == null,
      );

      final result = await viewModel.deleteProduct(context, plain.id);

      expect(result, isTrue);
      expect(mockStorageService.deletedArModelPaths, isEmpty);
    });
  });

  group('AdminProductManagementViewModel - Categories Mode (Phase 8.8)', () {
    test('loads the five seeded categories, excluding no genuine kind', () {
      final categories = viewModel.filteredCategories;

      for (final key in CommerceCategoryModel.seededCategoryIds) {
        expect(
          categories.any((c) => c.categoryId == key),
          isTrue,
          reason: 'missing seeded category $key',
        );
      }
      expect(categories.length, CommerceCategoryModel.seededCategoryIds.length);
    });

    testWidgets('product count is derived from the real categoryId '
        'reference (Phase 8.8b) and updates reactively', (tester) async {
      final context = await _pumpContext(tester);
      final furnitureCategory = viewModel.filteredCategories.firstWhere(
        (c) => c.categoryId == 'furniture',
      );
      final initialCount = furnitureCategory.productCount;
      expect(initialCount, greaterThan(0));

      final productToDelete = mockDatabase.products.firstWhere(
        (p) => p.categoryId == 'furniture',
      );
      await viewModel.deleteProduct(context, productToDelete.id);

      final updatedFurnitureCategory = viewModel.filteredCategories.firstWhere(
        (c) => c.categoryId == 'furniture',
      );
      expect(updatedFurnitureCategory.productCount, initialCount - 1);
    });

    test('categories sort by most/fewest products works', () {
      viewModel.setCategorySortOption(AdminCategorySortOption.mostProducts);
      var sorted = viewModel.filteredCategories;
      for (int i = 0; i < sorted.length - 1; i++) {
        expect(sorted[i].productCount >= sorted[i + 1].productCount, isTrue);
      }

      viewModel.setCategorySortOption(AdminCategorySortOption.fewestProducts);
      sorted = viewModel.filteredCategories;
      for (int i = 0; i < sorted.length - 1; i++) {
        expect(sorted[i].productCount <= sorted[i + 1].productCount, isTrue);
      }
    });

    group('deleteCategory - eligibility (ViewModel/repository boundary)', () {
      test('a seeded category can never be deleted', () {
        final furniture = viewModel.filteredCategories.firstWhere(
          (c) => c.categoryId == 'furniture',
        );
        expect(viewModel.canDeleteCategory(furniture), isFalse);
        expect(
          viewModel.categoryDeletionBlockedReason(furniture),
          contains('built-in'),
        );
      });

      test('a custom category with products still referencing it cannot be '
          'deleted (direct rule test exercising canDeleteCategory/'
          'categoryDeletionBlockedReason in isolation - see the '
          'end-to-end version below using real product data)', () {
        const custom = CommerceCategoryModel(
          categoryId: 'outdoor-furniture',
          name: 'Outdoor Furniture',
          key: 'outdoor-furniture',
          kind: ProductCategory.furniture,
          imageUrl: '',
          isActive: true,
          sortOrder: 60,
        );
        final item = AdminCategoryViewItem(category: custom, productCount: 3);

        expect(viewModel.canDeleteCategory(item), isFalse);
        expect(
          viewModel.categoryDeletionBlockedReason(item),
          contains('3 products'),
        );
      });

      test('a new custom category has zero products until a real product '
          'is assigned to it, then blocks deletion (Phase 8.8b end-to-end: '
          'a product can now genuinely reference an Admin-created '
          'category, not just the five seeded ones)', () async {
        final created = await mockCategoryRepository.addCategory(
          name: 'Outdoor Furniture',
          kind: ProductCategory.furniture,
        );
        var item = viewModel.filteredCategories.firstWhere(
          (c) => c.categoryId == created.categoryId,
        );
        expect(item.productCount, 0);
        expect(viewModel.canDeleteCategory(item), isTrue);

        final aProduct = mockDatabase.products.first;
        await mockDatabase.updateProduct(
          aProduct.copyWith(
            categoryId: created.categoryId,
            categoryKind: created.kind,
          ),
        );

        item = viewModel.filteredCategories.firstWhere(
          (c) => c.categoryId == created.categoryId,
        );
        expect(item.productCount, 1);
        expect(viewModel.canDeleteCategory(item), isFalse);
      });

      testWidgets('deletes a custom zero-product category, best-effort '
          'deleting its image only after the document is gone', (tester) async {
        final context = await _pumpContext(tester);
        final created = await mockCategoryRepository.addCategory(
          name: 'Outdoor Furniture',
          kind: ProductCategory.furniture,
          imageUrl: 'https://img.example/outdoor.png',
        );
        final item = viewModel.filteredCategories.firstWhere(
          (c) => c.categoryId == created.categoryId,
        );

        final result = await viewModel.deleteCategory(context, item);

        expect(result, isTrue);
        expect(
          viewModel.filteredCategories.any(
            (c) => c.categoryId == created.categoryId,
          ),
          isFalse,
        );
        expect(mockStorageService.deletedCategoryImageUrls, [
          'https://img.example/outdoor.png',
        ]);
        await _settleToast(tester);
      });

      testWidgets('refuses to delete a seeded category even if called '
          'directly, bypassing the View', (tester) async {
        final context = await _pumpContext(tester);
        final furniture = viewModel.filteredCategories.firstWhere(
          (c) => c.categoryId == 'furniture',
        );

        final result = await viewModel.deleteCategory(context, furniture);

        expect(result, isFalse);
        expect(
          viewModel.filteredCategories.any((c) => c.categoryId == 'furniture'),
          isTrue,
        );
        await _settleToast(tester);
      });

      testWidgets('a second concurrent delete submit is ignored while the '
          'first is still in flight (duplicate-submit prevention)', (
        tester,
      ) async {
        final context = await _pumpContext(tester);
        final a = await mockCategoryRepository.addCategory(
          name: 'Category A',
          kind: ProductCategory.decor,
        );
        final b = await mockCategoryRepository.addCategory(
          name: 'Category B',
          kind: ProductCategory.decor,
        );
        final itemA = viewModel.filteredCategories.firstWhere(
          (c) => c.categoryId == a.categoryId,
        );
        final itemB = viewModel.filteredCategories.firstWhere(
          (c) => c.categoryId == b.categoryId,
        );

        final first = viewModel.deleteCategory(context, itemA);
        expect(viewModel.isDeletingCategory, isTrue);

        final second = await viewModel.deleteCategory(context, itemB);
        expect(second, isFalse); // dropped - a delete was already in flight

        final firstResult = await first;
        expect(firstResult, isTrue);
        expect(
          viewModel.filteredCategories.any((c) => c.categoryId == b.categoryId),
          isTrue, // never deleted
        );
        await _settleToast(tester);
      });
    });
  });
}

/// Real seed data/reads, but `deleteProduct` throws - used only by the
/// Phase 8.6 error-handling test above.
class _ThrowingDeleteDatabase extends MockCommerceDatabase {
  @override
  Future<void> deleteProduct(String productId) =>
      Future.error(StateError('boom'));
}
