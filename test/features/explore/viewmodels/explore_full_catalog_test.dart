import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/routes/explore_launch_intent.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
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

  // A fully valid, renderable AR contract - `ProductArMetadata.isRenderable`
  // requires a well-formed storagePath/sha256/positive dimensions. Used by
  // fixtures that must represent a GENUINELY AR-eligible product, as
  // distinct from one that merely carries the raw `roomAr` experience type
  // with no real model (the exact distinction the "AR Available" filter
  // must respect - see `ExploreViewModel.filteredProducts`'s capability
  // filter and `ProductSummaryModel.arRenderable`).
  final renderableArMetadata = ProductArMetadata(
    storagePath: 'products/fixture/ar/model-v1.glb',
    modelVersion: '1',
    sha256: List.filled(64, 'a').join(),
    widthM: 1.0,
    depthM: 1.0,
    heightM: 1.0,
  );

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
    ProductArMetadata? arMetadata,
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
      arMetadata: arMetadata,
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
        arMetadata: renderableArMetadata,
      ),
    );
    await db.addProduct(
      product(
        't-instock-ar-beige',
        kind: ProductCategory.furniture,
        stock: 3,
        experience: ProductExperienceType.roomAr,
        colors: {ProductColorOption.beige},
        arMetadata: renderableArMetadata,
      ),
    );
    // A product that carries the raw `roomAr` experience type but has NO
    // renderable model contract - a placeholder/misconfigured listing. The
    // "AR Available" filter must NOT treat this as AR-eligible (it can't
    // actually promise a working Room-AR launch); it must still show up the
    // moment AR is deselected, exactly like an ordinary non-AR product.
    await db.addProduct(
      product(
        't-instock-rawflag-only-beige',
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
        't-instock-nonar-beige',
        kind: ProductCategory.clothing,
        stock: 3,
        colors: {ProductColorOption.beige},
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
    // every result genuinely matches all three, and is a GENUINELY
    // renderable AR model - not merely the raw `roomAr` experience type.
    for (final p in vm.filteredProducts) {
      expect(p.summary.inStock, true);
      expect(p.summary.arEnabled, true);
      expect(p.summary.arRenderable, true);
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
    expect(
      vm.filteredProducts.any(
        (p) => p.summary.id == 't-instock-rawflag-only-beige',
      ),
      false,
      reason:
          'raw roomAr experience type with no renderable model must NOT '
          'count as "AR Available"',
    );
  });

  test('AR Available filters on the genuine renderable Room-AR contract, '
      'not the raw experience-type flag', () {
    vm.clearAllFilters();
    vm.applyFilters(const ExploreFilterState(arAvailable: true));

    final ids = vm.filteredProducts.map((p) => p.summary.id).toSet();
    expect(ids.contains('t-instock-ar-beige'), true);
    expect(
      ids.contains('t-instock-rawflag-only-beige'),
      false,
      reason: 'has experienceType roomAr but no valid ProductArMetadata',
    );
    for (final p in vm.filteredProducts) {
      expect(p.summary.arRenderable, true);
    }
  });

  test('deselecting AR Available removes the AR restriction and '
      'immediately surfaces matching non-AR products, without hiding the '
      'AR ones still satisfying every other active filter (positive '
      'filter semantics)', () {
    // Start from the Figma default: In Stock + AR + Beige.
    final before = vm.filteredProducts.map((p) => p.summary.id).toSet();
    expect(before.contains('t-instock-ar-beige'), true);
    expect(before.contains('t-instock-nonar-beige'), false);
    expect(before.contains('t-instock-rawflag-only-beige'), false);

    // Remove ONLY the AR chip (mirrors AppliedFilterChips' onFilterRemoved
    // and the filter sheet's toggle-off — both call this exact copyWith).
    vm.applyFilters(vm.activeFilterState.copyWith(arAvailable: false));

    final after = vm.filteredProducts.map((p) => p.summary.id).toSet();
    expect(vm.activeFilterState.arAvailable, false);
    // Beige + In Stock is unchanged, so the widened set is a strict
    // superset: the AR item is still there (positive filter, never hidden)
    // AND the non-AR / raw-flag-only beige items are now included too.
    expect(after.containsAll(before), true);
    expect(after.contains('t-instock-nonar-beige'), true);
    expect(after.contains('t-instock-rawflag-only-beige'), true);
    expect(after.length, greaterThan(before.length));
  });

  test('removing one chip (e.g. Beige) while AR + In Stock stay active only '
      'widens along that one dimension - mirrors AppliedFilterChips\' '
      'per-chip onFilterRemoved', () {
    final beigeOn = vm.filteredProducts.map((p) => p.summary.id).toSet();

    // AppliedFilterChips' Beige chip calls exactly this copyWith.
    vm.applyFilters(
      vm.activeFilterState.copyWith(
        selectedColors: Set.of(vm.activeFilterState.selectedColors)
          ..remove(ProductColorOption.beige),
      ),
    );

    expect(vm.activeFilterState.selectedColors, isEmpty);
    expect(vm.activeFilterState.arAvailable, true);
    expect(vm.activeFilterState.inStockOnly, true);
    final beigeOff = vm.filteredProducts.map((p) => p.summary.id).toSet();
    // Still AR-gated and in-stock-gated, so the raw-flag-only / non-AR
    // fixtures remain excluded, but a non-beige AR item may now appear.
    expect(beigeOff.containsAll(beigeOn), true);
    expect(beigeOff.contains('t-instock-rawflag-only-beige'), false);
    expect(beigeOff.contains('t-instock-nonar-gray'), false);
  });

  test('selecting the "All" category chip (All Products) never touches '
      'AR / Beige / In Stock - only the category dimension changes', () {
    vm.setCategory(ProductCategory.furniture);
    expect(vm.activeFilterState.arAvailable, true);
    expect(vm.activeFilterState.inStockOnly, true);
    expect(vm.activeFilterState.selectedColors, {ProductColorOption.beige});

    vm.setCategory(ProductCategory.all);

    expect(vm.activeFilterState.category, ProductCategory.all);
    expect(vm.activeFilterState.categoryId, isNull);
    // AR/Beige/In Stock survive the category round-trip untouched - "All
    // Products" is not what clears the AR restriction; deselecting the AR
    // chip itself is (see the dedicated deselect test above).
    expect(vm.activeFilterState.arAvailable, true);
    expect(vm.activeFilterState.inStockOnly, true);
    expect(vm.activeFilterState.selectedColors, {ProductColorOption.beige});
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
      expect(p.summary.inStock && p.summary.arRenderable, true);
      expect(p.colors.contains(ProductColorOption.beige), true);
    }
    // count is exactly the number of eligible products matching all three
    // (using the same `arRenderable` predicate the viewmodel filters on)
    final expected = db.products.where((p) {
      final c = p.toCatalogModel();
      return p.isActive &&
          p.publicationStatus == ProductPublicationStatus.published &&
          c.summary.inStock &&
          c.summary.arRenderable &&
          c.colors.contains(ProductColorOption.beige);
    }).length;
    expect(filtered.length, expected);
    expect(
      filtered.any((p) => p.summary.id == 't-instock-rawflag-only-beige'),
      false,
    );
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
