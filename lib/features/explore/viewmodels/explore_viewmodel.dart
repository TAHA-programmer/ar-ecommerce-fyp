import 'package:flutter/foundation.dart';
import '../../../core/data/category_repository.dart';
import '../../../core/data/commerce_database.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/models/product/product_category.dart';
import '../models/catalog_product_model.dart';
import '../models/explore_filter_state.dart';
import '../models/explore_sort_option.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../app/routes/explore_launch_intent.dart';
import '../repositories/explore_repository.dart';
import '../../product_details/repositories/product_details_repository.dart';

class ExploreViewModel extends ChangeNotifier {
  final ExploreRepository _repository;
  final ProductDetailsRepository _productDetailsRepository;
  final CustomerShoppingState _shoppingState;
  final CommerceDatabase _db;
  final CategoryRepository _categoryRepository;

  ExploreViewModel(
    this._repository,
    this._productDetailsRepository,
    this._shoppingState,
    this._db,
    this._categoryRepository,
  ) {
    _shoppingState.addListener(_onShoppingStateChanged);
    _db.addListener(_onDbChanged);
  }

  void _onShoppingStateChanged() {
    notifyListeners();
  }

  void _onDbChanged() {
    // When DB changes, clear load state and reload catalog
    _hasLoaded = false;
    loadCatalog();
  }

  @override
  void dispose() {
    _shoppingState.removeListener(_onShoppingStateChanged);
    _db.removeListener(_onDbChanged);
    super.dispose();
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  List<String>? _intentProductIds;

  /// `true` while a Home ranked "See all" ("Top Rated", Featured) is showing:
  /// the intent's `productIds` arrive pre-ordered and that order is kept
  /// until the user picks an explicit sort (`applySort`) or the pin is
  /// cleared (`refresh`).
  bool _preserveIntentOrder = false;

  List<CatalogProductModel> _baseCatalog = [];

  String _searchText = '';
  String get searchText => _searchText;

  // Initial Figma state requires these filters to be active
  ExploreFilterState _activeFilterState = const ExploreFilterState(
    inStockOnly: true,
    arAvailable: true,
    selectedColors: {ProductColorOption.beige},
  );
  ExploreFilterState get activeFilterState => _activeFilterState;

  ExploreSortOption _activeSortOption = ExploreSortOption.recommended;
  ExploreSortOption get activeSortOption => _activeSortOption;

  // Quick category access (mirrors filter state category)
  ProductCategory get activeCategory => _activeFilterState.category;

  /// Resolved display name for an active exact-category filter (e.g. a Home
  /// tile launch), for the screen header - falls back to the first matching
  /// product's `categoryKind.label` if the category can't be resolved in
  /// this session (Decision C: inactive-for-customer, deleted, or the
  /// repository still loading). `null` only if no exact filter is active.
  String? get activeCategoryName {
    final categoryId = _activeFilterState.categoryId;
    if (categoryId == null) return null;
    final resolvedName = _categoryRepository.byId(categoryId)?.name;
    if (resolvedName != null) return resolvedName;
    for (final p in _baseCatalog) {
      if (p.categoryId == categoryId) return p.categoryKind.label;
    }
    return null;
  }

  int get cartCount => _shoppingState.cartCount;

  bool isFavorite(String productId) => _shoppingState.isFavorite(productId);

  /// Returns `null` on success or a clean, `AppToast`-ready error message.
  Future<String?> toggleFavorite(String productId) =>
      _shoppingState.toggleFavorite(productId);

  Future<String?> addToCart(String productId) async {
    try {
      final details = await _productDetailsRepository.getProductDetails(
        productId,
      );
      final defaultColor =
          details.defaultColor ??
          (details.availableColors.isNotEmpty
              ? details.availableColors.first
              : null);
      final defaultSize =
          details.defaultSize ??
          (details.availableSizes.isNotEmpty
              ? details.availableSizes.first
              : null);

      return await _shoppingState.addToCart(
        productId,
        selectedColor: defaultColor,
        selectedSize: defaultSize,
        priceAmountSnapshot: _extractPriceAmount(details.summary.currentPrice),
      );
    } catch (e) {
      return await _shoppingState.addToCart(productId);
    }
  }

  int _extractPriceAmount(String currentPrice) {
    final rawString = currentPrice.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(rawString) ?? 0;
  }

  bool _hasLoaded = false;

  Future<void> loadCatalog() async {
    if (_hasLoaded) return;
    _isLoading = true;
    notifyListeners();

    try {
      _baseCatalog = await _repository.getCatalog();
    } catch (e) {
      debugPrint('Failed to load explore catalog: $e');
    } finally {
      _hasLoaded = true;
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    try {
      // Reset to default first-time explore state
      _searchText = '';
      _intentProductIds = null;
      _preserveIntentOrder = false;
      _activeFilterState = const ExploreFilterState(
        inStockOnly: true,
        arAvailable: true,
        selectedColors: {ProductColorOption.beige},
      );
      _activeSortOption = ExploreSortOption.recommended;

      await _repository.refresh();
      _baseCatalog = await _repository.getCatalog();
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to refresh explore catalog: $e');
    }
  }

  void updateSearchText(String text) {
    _searchText = text;
    notifyListeners();
  }

  void setCategory(ProductCategory category) {
    _activeFilterState = _activeFilterState.copyWith(category: category);
    notifyListeners();
  }

  void applyFilters(ExploreFilterState newFilterState) {
    _activeFilterState = newFilterState;
    notifyListeners();
  }

  void clearAllFilters() {
    // Keeps search text, but resets filters to default
    _activeFilterState = ExploreFilterState.defaultState();
    notifyListeners();
  }

  void applySort(ExploreSortOption newSortOption) {
    _activeSortOption = newSortOption;
    // The user has expressed an explicit ordering preference — drop the
    // "keep the Home ranked order" pin.
    _preserveIntentOrder = false;
    notifyListeners();
  }

  void applyIntent(ExploreLaunchIntent intent) {
    if (intent.fromHome) {
      // A Home-originated navigation ("See all", hero CTA, category tile,
      // search) must start from a clean slate — never inherit the Explore
      // tab's persisted / Figma-default filters. It then applies ONLY the
      // one preset dimension below. The direct Explore-tab open passes no
      // intent, so its session state is untouched.
      _searchText = '';
      _activeFilterState = const ExploreFilterState();
      _activeSortOption = ExploreSortOption.recommended;
      _intentProductIds = null;
      _preserveIntentOrder = false;
    }

    if (intent.searchQuery != null) {
      _searchText = intent.searchQuery!;
    }

    _activeFilterState = _activeFilterState.copyWith(
      category: intent.categoryId == null ? intent.category : null,
      categoryId: intent.categoryId,
      arAvailable: intent.arOnly ? true : null,
      tryOnAvailable: intent.tryOnOnly ? true : null,
    );

    if (intent.sortOption != null) {
      _activeSortOption = intent.sortOption!;
    }

    if (intent.productIds != null) {
      _intentProductIds = intent.productIds;
      // A Home ranked list ("Top Rated" / Featured) arrives pre-ordered;
      // preserve that order under the neutral sort until the user re-sorts.
      _preserveIntentOrder = intent.fromHome;
    }

    notifyListeners();
  }

  List<CatalogProductModel> get filteredProducts {
    List<CatalogProductModel> results = List.from(_baseCatalog);

    if (_intentProductIds != null) {
      results = results
          .where((p) => _intentProductIds!.contains(p.summary.id))
          .toList();
    }

    // 1. Search - matches title, broad kind label, and the product's real
    // assigned category name (e.g. "Outdoor" finds products in a custom
    // "Outdoor Furniture" category, not just "Furniture"-kind products).
    // The categoryId->name lookup is built once per filter pass, not once
    // per product, to keep this an O(n) scan (Phase 8.8b, review point 5).
    if (_searchText.isNotEmpty) {
      final query = _searchText.toLowerCase();
      final categoryNameById = {
        for (final c in _categoryRepository.categories) c.categoryId: c.name,
      };
      results = results.where((p) {
        final categoryName = categoryNameById[p.categoryId] ?? '';
        return p.summary.title.toLowerCase().contains(query) ||
            p.categoryKind.label.toLowerCase().contains(query) ||
            categoryName.toLowerCase().contains(query);
      }).toList();
    }

    // 2. Category - exact categoryId (e.g. a Home tile) takes precedence
    // over the broad categoryKind chips filter; the two are mutually
    // exclusive in ExploreFilterState.copyWith, so at most one is ever set.
    if (_activeFilterState.categoryId != null) {
      results = results
          .where((p) => p.categoryId == _activeFilterState.categoryId)
          .toList();
    } else if (_activeFilterState.category != ProductCategory.all) {
      results = results
          .where((p) => p.categoryKind == _activeFilterState.category)
          .toList();
    }

    // 3. Price Range
    results = results
        .where(
          (p) =>
              p.priceAmount >= _activeFilterState.minimumPrice &&
              p.priceAmount <= _activeFilterState.maximumPrice,
        )
        .toList();

    // 4. Stock
    if (_activeFilterState.inStockOnly) {
      results = results.where((p) => p.summary.inStock).toList();
    }

    // 5. Capabilities (AR / Try-On)
    // If both selected, it's AR OR TryOn
    if (_activeFilterState.arAvailable || _activeFilterState.tryOnAvailable) {
      results = results.where((p) {
        bool match = false;
        if (_activeFilterState.arAvailable && p.summary.arEnabled) {
          match = true;
        }
        if (_activeFilterState.tryOnAvailable && p.summary.tryOnEnabled) {
          match = true;
        }
        return match;
      }).toList();
    }

    // 6. Sizes (OR within sizes)
    if (_activeFilterState.selectedSizes.isNotEmpty) {
      results = results.where((p) {
        return p.sizes
            .intersection(_activeFilterState.selectedSizes)
            .isNotEmpty;
      }).toList();
    }

    // 7. Colors (OR within colors)
    if (_activeFilterState.selectedColors.isNotEmpty) {
      results = results.where((p) {
        return p.colors
            .intersection(_activeFilterState.selectedColors)
            .isNotEmpty;
      }).toList();
    }

    // 8. Sorting
    if (_preserveIntentOrder && _intentProductIds != null) {
      // Render a Home ranked "See all" in exactly the order Home supplied
      // (any product not in the list — shouldn't happen — sinks to the end).
      final order = <String, int>{};
      for (var i = 0; i < _intentProductIds!.length; i++) {
        order[_intentProductIds![i]] = i;
      }
      results.sort(
        (a, b) => (order[a.summary.id] ?? 1 << 30).compareTo(
          order[b.summary.id] ?? 1 << 30,
        ),
      );
      return results;
    }
    switch (_activeSortOption) {
      case ExploreSortOption.recommended:
        results.sort(
          (a, b) => a.recommendationRank.compareTo(b.recommendationRank),
        );
        break;
      case ExploreSortOption.newest:
        results.sort(
          (a, b) => b.addedDate.compareTo(a.addedDate),
        ); // Descending date
        break;
      case ExploreSortOption.priceLowToHigh:
        results.sort((a, b) => a.priceAmount.compareTo(b.priceAmount));
        break;
      case ExploreSortOption.priceHighToLow:
        results.sort((a, b) => b.priceAmount.compareTo(a.priceAmount));
        break;
      case ExploreSortOption.mostPopular:
        results.sort(
          (a, b) => b.popularityScore.compareTo(a.popularityScore),
        ); // Descending score
        break;
    }

    return results;
  }
}
