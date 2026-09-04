import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/features/explore/viewmodels/explore_viewmodel.dart';
import 'package:twin_ar/features/explore/repositories/mock_explore_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/app/routes/explore_launch_intent.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';

void main() {
  late ExploreViewModel viewModel;
  late MockExploreRepository mockRepository;
  late CustomerShoppingState shoppingState;
  late MockCommerceDatabase db;
  late MockCategoryRepository categoryRepository;

  setUp(() {
    db = MockCommerceDatabase();
    mockRepository = MockExploreRepository(db);
    shoppingState = CustomerShoppingState(
      MockFavoritesRepository(),
      MockCartRepository(),
    );
    categoryRepository = MockCategoryRepository();
    viewModel = ExploreViewModel(
      mockRepository,
      MockProductDetailsRepository(db, simulateDelay: false),
      shoppingState,
      db,
      categoryRepository,
    );
  });

  group('ExploreViewModel Tests', () {
    test('initial state has correct default filters', () {
      expect(viewModel.isLoading, true);
      expect(viewModel.activeFilterState.inStockOnly, true);
      expect(viewModel.activeFilterState.arAvailable, true);
      expect(viewModel.activeFilterState.selectedColors.isNotEmpty, true);
      expect(viewModel.cartCount, 0);
    });

    test(
      'loadCatalog populates items and applies initial filter to 24 results',
      () async {
        await viewModel.loadCatalog();

        expect(viewModel.isLoading, false);
        // Wait for it to filter, actually it filters synchronously in the getter.
        expect(viewModel.filteredProducts.length, 24);
      },
    );

    test('addToCart increments shared state', () async {
      await viewModel.loadCatalog();
      final product = viewModel.filteredProducts.first;

      await viewModel.addToCart(product.summary.id);

      expect(shoppingState.cartCount, 1);
    });

    test(
      'clearAllFilters resets to default and returns all products',
      () async {
        await viewModel.loadCatalog();
        viewModel.clearAllFilters();
        // Total mock products is roughly 50, but let's just assert it is > 24
        expect(viewModel.filteredProducts.length, greaterThan(24));
      },
    );

    group('Phase 8.8b - exact categoryId vs. broad categoryKind filtering', () {
      test('an exact categoryId filter shows only that category\'s products, '
          'never every product sharing its broad kind - tapping "Outdoor '
          'Furniture" must not show every Furniture-kind product', () async {
        await viewModel.loadCatalog();
        final baselineFurnitureCount = viewModel.filteredProducts
            .where((p) => p.categoryKind == ProductCategory.furniture)
            .length;
        expect(
          baselineFurnitureCount,
          greaterThan(1),
          reason: 'test setup needs more than one furniture-kind product',
        );

        // Reassign exactly one furniture-kind product to a brand-new
        // custom category sharing the same broad kind, so "exact" and
        // "broad" filtering are genuinely distinguishable.
        final custom = await categoryRepository.addCategory(
          name: 'Outdoor Furniture',
          kind: ProductCategory.furniture,
        );
        final target = viewModel.filteredProducts.firstWhere(
          (p) => p.categoryKind == ProductCategory.furniture,
        );
        await db.updateProduct(
          db
              .getProductById(target.summary.id)
              .copyWith(
                categoryId: custom.categoryId,
                categoryKind: custom.kind,
              ),
        );
        await viewModel.loadCatalog();
        viewModel.clearAllFilters();

        viewModel.applyIntent(
          ExploreLaunchIntent(categoryId: custom.categoryId),
        );

        expect(viewModel.filteredProducts.map((p) => p.summary.id).toList(), [
          target.summary.id,
        ]);
      });

      test('a broad categoryKind chip still shows every product of that '
          'kind, unchanged from pre-Phase-8.8b behavior', () async {
        await viewModel.loadCatalog();
        viewModel.clearAllFilters();
        viewModel.setCategory(ProductCategory.furniture);

        expect(
          viewModel.filteredProducts.every(
            (p) => p.categoryKind == ProductCategory.furniture,
          ),
          isTrue,
        );
        expect(viewModel.activeFilterState.categoryId, isNull);
      });

      test('selecting a kind chip clears an active exact categoryId filter, '
          'and vice versa - at most one is ever active', () async {
        await viewModel.loadCatalog();
        viewModel.applyIntent(
          const ExploreLaunchIntent(categoryId: 'furniture'),
        );
        expect(viewModel.activeFilterState.categoryId, 'furniture');

        viewModel.setCategory(ProductCategory.clothing);
        expect(viewModel.activeFilterState.categoryId, isNull);
        expect(viewModel.activeFilterState.category, ProductCategory.clothing);
      });

      test('activeCategoryName resolves the real category name for an '
          'exact-category filter', () async {
        await viewModel.loadCatalog();
        viewModel.applyIntent(
          const ExploreLaunchIntent(categoryId: 'furniture'),
        );

        expect(viewModel.activeCategoryName, 'Furniture');
      });

      test('search matches a product\'s real assigned category name, not '
          'just its broad kind label', () async {
        final custom = await categoryRepository.addCategory(
          name: 'Outdoor Furniture',
          kind: ProductCategory.furniture,
        );
        await viewModel.loadCatalog();
        final aProduct = viewModel.filteredProducts.firstWhere(
          (p) => p.categoryKind == ProductCategory.furniture,
        );
        await db.updateProduct(
          db
              .getProductById(aProduct.summary.id)
              .copyWith(
                categoryId: custom.categoryId,
                categoryKind: custom.kind,
              ),
        );
        // The database's own change notification triggers an async
        // reload internally (ExploreViewModel._onDbChanged) - awaiting
        // loadCatalog() again here (it no longer short-circuits, since
        // _hasLoaded was already reset to false by that listener) makes
        // sure _baseCatalog reflects the reassignment before asserting.
        await viewModel.loadCatalog();
        viewModel.clearAllFilters();

        viewModel.updateSearchText('Outdoor');

        expect(
          viewModel.filteredProducts.any(
            (p) => p.summary.id == aProduct.summary.id,
          ),
          isTrue,
        );
      });
    });
  });
}
