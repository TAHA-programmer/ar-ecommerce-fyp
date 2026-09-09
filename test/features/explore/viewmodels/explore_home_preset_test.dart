import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/routes/explore_launch_intent.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/features/explore/models/explore_sort_option.dart';
import 'package:twin_ar/features/explore/repositories/mock_explore_repository.dart';
import 'package:twin_ar/features/explore/viewmodels/explore_viewmodel.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

/// Stage 1 — Home-originated "See all" / hero / category / search navigation
/// must land on a NEUTRAL Explore state + exactly the one intended preset,
/// never inheriting the Explore tab's Figma-default (In Stock + AR + Beige)
/// or a prior manual filter. The direct Explore-tab default and normal
/// in-Explore persistence are unchanged.
void main() {
  late ExploreViewModel vm;
  late MockCommerceDatabase db;

  setUp(() async {
    db = MockCommerceDatabase();
    vm = ExploreViewModel(
      MockExploreRepository(db),
      MockProductDetailsRepository(db, simulateDelay: false),
      CustomerShoppingState(MockFavoritesRepository(), MockCartRepository()),
      db,
      MockCategoryRepository(),
    );
    await vm.loadCatalog();
  });

  test('the Explore tab default is still the Figma state (In Stock + AR + '
      'Beige) — untouched by Stage 1', () {
    expect(vm.activeFilterState.inStockOnly, true);
    expect(vm.activeFilterState.arAvailable, true);
    expect(vm.activeFilterState.selectedColors, {ProductColorOption.beige});
  });

  test('a fromHome AR intent clears In Stock + Beige and applies ONLY AR', () {
    vm.applyIntent(const ExploreLaunchIntent(fromHome: true, arOnly: true));

    final s = vm.activeFilterState;
    expect(s.arAvailable, true);
    expect(s.inStockOnly, false);
    expect(s.selectedColors, isEmpty);
    expect(s.tryOnAvailable, false);
    expect(s.category, ProductCategory.all);
    expect(vm.searchText, '');
    expect(vm.activeSortOption, ExploreSortOption.recommended);
    // every result genuinely matches only the AR preset
    expect(vm.filteredProducts, isNotEmpty);
    expect(vm.filteredProducts.every((p) => p.summary.arEnabled), true);
  });

  test('a fromHome Try-On intent applies ONLY Try-On', () {
    vm.applyIntent(const ExploreLaunchIntent(fromHome: true, tryOnOnly: true));
    final s = vm.activeFilterState;
    expect(s.tryOnAvailable, true);
    expect(s.arAvailable, false);
    expect(s.inStockOnly, false);
    expect(s.selectedColors, isEmpty);
    expect(vm.filteredProducts.every((p) => p.summary.tryOnEnabled), true);
  });

  test('a fromHome newest intent applies neutral filters + newest sort', () {
    vm.applyIntent(
      const ExploreLaunchIntent(
        fromHome: true,
        sortOption: ExploreSortOption.newest,
      ),
    );
    expect(vm.activeSortOption, ExploreSortOption.newest);
    expect(vm.activeFilterState.hasActiveFilters, false);
    final dates = vm.filteredProducts.map((p) => p.addedDate).toList();
    for (var i = 1; i < dates.length; i++) {
      expect(dates[i - 1].isBefore(dates[i]), false);
    }
  });

  test('a fromHome category intent applies ONLY that category', () {
    vm.applyIntent(
      const ExploreLaunchIntent(fromHome: true, categoryId: 'furniture'),
    );
    expect(vm.activeFilterState.categoryId, 'furniture');
    expect(vm.activeFilterState.inStockOnly, false);
    expect(vm.activeFilterState.arAvailable, false);
    expect(vm.filteredProducts, isNotEmpty);
    expect(vm.filteredProducts.every((p) => p.categoryId == 'furniture'), true);
  });

  test('a fromHome ranked productIds intent renders in the given order under '
      'the neutral sort', () {
    final ranked = vm.filteredProducts
        .map((p) => p.summary.id)
        .take(6)
        .toList()
        .reversed
        .toList();

    vm.applyIntent(ExploreLaunchIntent(fromHome: true, productIds: ranked));

    expect(vm.filteredProducts.map((p) => p.summary.id).toList(), ranked);
  });

  test('picking an explicit sort drops the Home ranked-order pin', () {
    final ranked = vm.filteredProducts
        .map((p) => p.summary.id)
        .take(6)
        .toList()
        .reversed
        .toList();
    vm.applyIntent(ExploreLaunchIntent(fromHome: true, productIds: ranked));
    expect(vm.filteredProducts.map((p) => p.summary.id).toList(), ranked);

    vm.applySort(ExploreSortOption.priceLowToHigh);

    final prices = vm.filteredProducts.map((p) => p.priceAmount).toList();
    for (var i = 1; i < prices.length; i++) {
      expect(prices[i - 1] <= prices[i], true);
    }
  });

  test(
    'after a fromHome preset, normal in-Explore filtering still persists',
    () {
      vm.applyIntent(const ExploreLaunchIntent(fromHome: true, arOnly: true));
      vm.applyFilters(vm.activeFilterState.copyWith(inStockOnly: true));
      expect(vm.activeFilterState.inStockOnly, true);
      expect(vm.activeFilterState.arAvailable, true);
      expect(vm.filteredProducts.every((p) => p.summary.inStock), true);
    },
  );

  test('a NON-fromHome intent still MERGES onto the current state '
      '(back-compat regression lock)', () {
    // start from the Figma default (In Stock + AR + Beige)
    vm.applyIntent(const ExploreLaunchIntent(arOnly: true));
    final s = vm.activeFilterState;
    expect(s.arAvailable, true);
    expect(s.inStockOnly, true); // NOT reset
    expect(s.selectedColors, {ProductColorOption.beige}); // NOT reset
  });
}
