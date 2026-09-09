import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/routes/explore_launch_intent.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_mappers.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_publication_status.dart';
import 'package:twin_ar/features/explore/models/explore_filter_state.dart';
import 'package:twin_ar/features/explore/models/explore_sort_option.dart';
import 'package:twin_ar/features/explore/repositories/mock_explore_repository.dart';
import 'package:twin_ar/features/explore/viewmodels/explore_viewmodel.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

/// Phase 9.3 pre-work — Explore must show the COMPLETE customer-eligible
/// catalogue (every `published && isActive` product) once filters are
/// cleared, with no arbitrary ~36 ceiling and no accidental persistence of
/// the Figma initial filters. `showInCatalog` is no longer a customer
/// Explore filter.
void main() {
  late MockCommerceDatabase db;
  late ExploreViewModel vm;

  ProductModel product(
    String id, {
    ProductCategory kind = ProductCategory.decor,
    String? categoryId,
    ProductPublicationStatus status = ProductPublicationStatus.published,
    bool isActive = true,
    int stock = 5,
    ProductExperienceType experience = ProductExperienceType.none,
    Set<ProductColorOption> colors = const {},
    bool showInCatalog = true,
    int rank = 40,
  }) {
    return ProductModel(
      id: id,
      sku: 'SKU-$id',
      title: id,
      description: 'x',
      categoryId: categoryId ?? kind.name,
      categoryKind: kind,
      subcategory: 'Sub',
      priceAmount: 1000,
      stockQuantity: stock,
      mainImage: const ProductImageRef(path: 'assets/x.png'),
      experienceType: experience,
      addedDate: DateTime(2026, 1, 1),
      isActive: isActive,
      showInCatalog: showInCatalog,
      publicationStatus: status,
      deliveryEstimate: '3-5 days',
      availableColors: colors,
      recommendationRank: rank,
    );
  }

  int eligibleInDb() => db.products
      .where(
        (p) =>
            p.isActive &&
            p.publicationStatus == ProductPublicationStatus.published,
      )
      .length;

  ExploreViewModel freshViewModel() => ExploreViewModel(
    MockExploreRepository(db),
    MockProductDetailsRepository(db, simulateDelay: false),
    CustomerShoppingState(MockFavoritesRepository(), MockCartRepository()),
    db,
    MockCategoryRepository(),
  );

  setUp(() async {
    db = MockCommerceDatabase();
    // A rich spread on top of the real 50-product seed. Deliberately mixes
    // every axis the filters care about.
    await db.addProduct(
      product('t-draft', status: ProductPublicationStatus.draft),
    );
    await db.addProduct(product('t-inactive', isActive: false));
    await db.addProduct(
      product(
        't-draft-inactive',
        status: ProductPublicationStatus.draft,
        isActive: false,
      ),
    );
    await db.addProduct(
      product(
        't-oos-ar-beige',
        kind: ProductCategory.furniture,
        stock: 0,
        experience: ProductExperienceType.roomAr,
        colors: {ProductColorOption.beige},
      ),
    );
    await db.addProduct(
      product(
        't-instock-ar-beige',
        kind: ProductCategory.furniture,
        stock: 3,
        experience: ProductExperienceType.roomAr,
        colors: {ProductColorOption.beige},
      ),
    );
    await db.addProduct(
      product(
        't-instock-nonar-gray',
        kind: ProductCategory.lighting,
        stock: 3,
        colors: {ProductColorOption.gray},
      ),
    );
    await db.addProduct(
      product(
        't-showincatalog-false',
        kind: ProductCategory.rugs,
        showInCatalog: false,
      ),
    );
    vm = freshViewModel();
    await vm.loadCatalog();
  });

  test('the Figma initial state (In Stock + AR + Beige) filters the full '
      'catalogue down - the filtered count is a strict subset', () {
    final filtered = vm.filteredProducts.length;
    expect(vm.activeFilterState.inStockOnly, true);
    expect(vm.activeFilterState.arAvailable, true);
    expect(vm.activeFilterState.selectedColors, {ProductColorOption.beige});
    expect(filtered, lessThan(eligibleInDb()));
    // every result genuinely matches all three
    for (final p in vm.filteredProducts) {
      expect(p.summary.inStock, true);
      expect(p.summary.arEnabled, true);
      expect(p.colors.contains(ProductColorOption.beige), true);
    }
    expect(
      vm.filteredProducts.any((p) => p.summary.id == 't-instock-ar-beige'),
      true,
    );
    expect(
      vm.filteredProducts.any((p) => p.summary.id == 't-oos-ar-beige'),
      false,
      reason: 'out of stock must be filtered out',
    );
  });

  test('Clear All + All category + empty search + Recommended sort shows the '
      'COMPLETE eligible catalogue, no ~36 ceiling, no hardcoded count', () {
    vm.clearAllFilters();
    vm.setCategory(ProductCategory.all);
    vm.updateSearchText('');
    vm.applySort(ExploreSortOption.recommended);

    expect(vm.filteredProducts.length, eligibleInDb());
    expect(
      vm.filteredProducts.length,
      greaterThan(36),
      reason: 'the old showInCatalog-curated Explore capped near 36',
    );
    // the showInCatalog:false product IS present now
    expect(
      vm.filteredProducts.any((p) => p.summary.id == 't-showincatalog-false'),
      true,
    );
  });

  test(
    'Clear All clears every advanced filter and all chip state together',
    () {
      vm.applyFilters(
        const ExploreFilterState(
          inStockOnly: true,
          arAvailable: true,
          tryOnAvailable: true,
          minimumPrice: 100,
          maximumPrice: 900,
          selectedColors: {ProductColorOption.beige, ProductColorOption.black},
          selectedSizes: {},
        ),
      );
      expect(vm.activeFilterState.hasActiveFilters, true);

      vm.clearAllFilters();

      final s = vm.activeFilterState;
      expect(s.hasActiveFilters, false);
      expect(s.inStockOnly, false);
      expect(s.arAvailable, false);
      expect(s.tryOnAvailable, false);
      expect(s.minimumPrice, 0);
      expect(s.maximumPrice, 50000);
      expect(s.selectedColors, isEmpty);
      expect(s.selectedSizes, isEmpty);
      expect(s.category, ProductCategory.all);
      expect(s.categoryId, isNull);
    },
  );

  test(
    'draft and inactive products never appear, in any filter combination',
    () {
      for (final combo in [
        () => vm.clearAllFilters(),
        () => vm.applyFilters(const ExploreFilterState(inStockOnly: true)),
        () => vm.applyFilters(const ExploreFilterState(arAvailable: true)),
        () => vm.setCategory(ProductCategory.furniture),
        () => vm.setCategory(ProductCategory.all),
      ]) {
        combo();
        final ids = vm.filteredProducts.map((p) => p.summary.id).toSet();
        expect(ids.contains('t-draft'), false);
        expect(ids.contains('t-inactive'), false);
        expect(ids.contains('t-draft-inactive'), false);
      }
    },
  );

  test('every category chip shows exactly its published+active members', () {
    vm.clearAllFilters();
    for (final kind in ProductCategory.values) {
      vm.setCategory(kind);
      final shown = vm.filteredProducts.map((p) => p.summary.id).toSet();
      final expected = db.products
          .where(
            (p) =>
                p.isActive &&
                p.publicationStatus == ProductPublicationStatus.published &&
                (kind == ProductCategory.all || p.categoryKind == kind),
          )
          .map((p) => p.id)
          .toSet();
      expect(shown, expected, reason: 'category chip: ${kind.name}');
    }
  });

  test('re-applying In Stock + AR + Beige after Clear All returns only '
      'matching products with an accurate count', () {
    vm.clearAllFilters();
    final full = vm.filteredProducts.length;

    vm.applyFilters(
      const ExploreFilterState(
        inStockOnly: true,
        arAvailable: true,
        selectedColors: {ProductColorOption.beige},
      ),
    );

    final filtered = vm.filteredProducts;
    expect(filtered.length, lessThan(full));
    for (final p in filtered) {
      expect(p.summary.inStock && p.summary.arEnabled, true);
      expect(p.colors.contains(ProductColorOption.beige), true);
    }
    // count is exactly the number of eligible products matching all three
    final expected = db.products.where((p) {
      final c = p.toCatalogModel();
      return p.isActive &&
          p.publicationStatus == ProductPublicationStatus.published &&
          c.summary.inStock &&
          c.summary.arEnabled &&
          c.colors.contains(ProductColorOption.beige);
    }).length;
    expect(filtered.length, expected);
  });

  test('category + advanced filters + search + sort combine correctly', () {
    vm.clearAllFilters();
    vm.setCategory(ProductCategory.furniture);
    vm.applyFilters(
      vm.activeFilterState.copyWith(
        inStockOnly: true,
        arAvailable: true,
        selectedColors: {ProductColorOption.beige},
      ),
    );
    vm.updateSearchText('t-instock-ar-beige');
    vm.applySort(ExploreSortOption.priceLowToHigh);

    expect(vm.filteredProducts.map((p) => p.summary.id).toList(), [
      't-instock-ar-beige',
    ]);
  });

  test('returning to All + Clear All restores the complete eligible set', () {
    vm.setCategory(ProductCategory.furniture);
    vm.applyFilters(const ExploreFilterState(inStockOnly: true));
    vm.updateSearchText('sofa');
    expect(vm.filteredProducts.length, lessThan(eligibleInDb()));

    vm.updateSearchText('');
    vm.clearAllFilters();
    vm.setCategory(ProductCategory.all);

    expect(vm.filteredProducts.length, eligibleInDb());
  });

  test('a fresh Explore session (reopen) starts at the Figma initial filters, '
      'not stale-restored from a previous session', () async {
    vm.clearAllFilters();
    expect(vm.activeFilterState.hasActiveFilters, false);

    // A brand-new ExploreViewModel over the same DB = "reopened Explore".
    final reopened = freshViewModel();
    await reopened.loadCatalog();

    expect(reopened.activeFilterState.inStockOnly, true);
    expect(reopened.activeFilterState.arAvailable, true);
    expect(reopened.activeFilterState.selectedColors, {
      ProductColorOption.beige,
    });
  });

  test('an intent-scoped launch does not permanently cap the catalogue after '
      'Clear All + refresh', () async {
    vm.applyIntent(
      const ExploreLaunchIntent(productIds: ['t-instock-ar-beige']),
    );
    expect(vm.filteredProducts.length, 1);

    // pull-to-refresh resets intent + filters to the default session state
    await vm.refresh();
    vm.clearAllFilters();
    vm.setCategory(ProductCategory.all);

    expect(vm.filteredProducts.length, eligibleInDb());
  });
}
