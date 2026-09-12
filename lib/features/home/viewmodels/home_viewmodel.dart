import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/data/commerce_database.dart';
import '../../../core/models/product/product_category.dart';
import '../../../core/models/product/product_mappers.dart';
import '../../../core/models/product/product_model.dart';
import '../../../core/models/product/product_publication_status.dart';
import '../../../core/models/product/product_summary_model.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../../product_details/repositories/recently_viewed_repository.dart';
import '../models/category_model.dart';
import '../models/home_banner_model.dart';
import '../repositories/home_repository.dart';
import '../repositories/product_stats_repository.dart';

/// Per-section lifecycle. Every Home section reports its own status so one
/// failing/empty section can never blank the others.
enum HomeSectionStatus { loading, ready, empty, error }

/// "Dynamic Home Content" — Stage 3 (`20_DYNAMIC_HOME_CONTENT_PLAN.md`).
///
/// Every Home product section is now backed by a **real signal**, resolved
/// against the live `CommerceDatabase` customer catalogue cache (the
/// `published && isActive` snapshot the app already maintains):
///
///  * **New Arrivals / AR Enabled / Virtual Try-On** — synchronous filters
///    over the cache (`addedDate` order / `hasRenderableArModel` /
///    `hasRenderableVtoAsset`). Recompute for free on [_onDbChanged].
///  * **Featured** — the explicit Admin `isFeatured` flag + `featuredRank`
///    (Stage 2 contract), cache-derived, hidden when nothing is featured.
///  * **Best Sellers** — `productStats.unitsSold` ordering ([ProductStatsRepository]),
///    ids resolved against the cache. When there is **no genuine positive
///    sales signal** (or the Stage 2 backend is not deployed / denies the
///    read), it falls back to the honest `rating` ranking and the View
///    labels it **"Top Rated"**, never "Best Sellers".
///  * **Popular Furniture & Decor** — `productStats.favoriteCount` ordering,
///    filtered to the furniture/decor kinds, same honest fallback →
///    **"Top Rated Furniture & Decor"**.
///  * **Recently Viewed** — the signed-in customer's own
///    `users/{uid}/recentlyViewed` history ([RecentlyViewedRepository]),
///    newest-first, resolved against the cache (deleted / draft / unpublished
///    / inactive products drop out), deduplicated. Hidden entirely when the
///    resolved history is empty; "See all" (the dedicated
///    `/recently-viewed` page) is offered only when > 3 eligible items exist.
///
/// The one independently-failing async section that can still surface an
/// error is **Shop by Category**. Statistics / view-history failures are
/// swallowed — the section falls back or hides, never an error strip and
/// never a retry loop.
class HomeViewModel extends ChangeNotifier {
  final HomeRepository _repository;
  final ProductDetailsRepository _productDetailsRepository;
  final CustomerShoppingState _shoppingState;
  final CommerceDatabase _db;
  final ProductStatsRepository _productStats;
  final RecentlyViewedRepository _recentlyViewed;

  static const int _sectionLimit = 3;

  /// How many ranked ids a "See all" preset carries into Explore — the full
  /// ranked list, not just the three shown, so the ordered-`productIds`
  /// Explore view is meaningful.
  static const int _seeAllLimit = 24;

  HomeViewModel(
    this._repository,
    this._productDetailsRepository,
    this._shoppingState,
    this._db,
    this._productStats,
    this._recentlyViewed,
  ) {
    _shoppingState.addListener(_onShoppingStateChanged);
    _db.addListener(_onDbChanged);
    // The catalogue cache may already be warm (e.g. the customer navigated
    // Explore → Home) — derive the product sections immediately.
    _recomputeSections();
  }

  void _onShoppingStateChanged() {
    // Favourite/cart state changed — no catalogue change, so the derived
    // section lists are still valid; just repaint the favourite hearts.
    notifyListeners();
  }

  void _onDbChanged() {
    // The catalogue changed under us (Admin edit, sign-in/out re-subscribe).
    // Recompute the derived sections synchronously so they update without a
    // spinner, then re-pull the async Categories + dynamic data.
    _recomputeSections();
    notifyListeners();
    unawaited(loadHomeData(force: true));
  }

  @override
  void dispose() {
    _shoppingState.removeListener(_onShoppingStateChanged);
    _db.removeListener(_onDbChanged);
    super.dispose();
  }

  // ── first-load / retry plumbing ──────────────────────────────────────────
  bool _firstLoadComplete = false;
  bool _loadInFlight = false;

  /// The full-screen branded spinner shows only until the first
  /// banners+categories load resolves. Product sections settle alongside it
  /// (the catalogue listener has virtually always delivered by then).
  bool get isLoading => !_firstLoadComplete;

  /// A cache-derived section is only "still loading" before the first load
  /// completes AND while the catalogue cache is genuinely still empty.
  bool get _catalogueSettled => _firstLoadComplete || _db.products.isNotEmpty;

  HomeSectionStatus _status(List<Object?> items) {
    if (items.isNotEmpty) return HomeSectionStatus.ready;
    return _catalogueSettled
        ? HomeSectionStatus.empty
        : HomeSectionStatus.loading;
  }

  // ── static: hero banners ─────────────────────────────────────────────────
  List<HomeBannerModel> _banners = const [];
  List<HomeBannerModel> get banners => _banners;

  // ── async: Shop by Category (the one independently-failing section) ───────
  List<CategoryModel> _categories = const [];
  HomeSectionStatus _categoriesStatus = HomeSectionStatus.loading;
  List<CategoryModel> get categories => _categories;
  HomeSectionStatus get categoriesStatus => _categoriesStatus;

  // ── cache-derived product sections ───────────────────────────────────────
  List<ProductSummaryModel> _newArrivals = const [];
  List<ProductSummaryModel> _arEnabled = const [];
  List<ProductSummaryModel> _virtualTryOn = const [];
  List<ProductSummaryModel> _featured = const [];
  List<String> _featuredSeeAllIds = const [];

  List<ProductSummaryModel> get newArrivals => _newArrivals;
  HomeSectionStatus get newArrivalsStatus => _status(_newArrivals);

  List<ProductSummaryModel> get arEnabledProducts => _arEnabled;
  HomeSectionStatus get arEnabledStatus => _status(_arEnabled);

  List<ProductSummaryModel> get virtualTryOnCollection => _virtualTryOn;
  HomeSectionStatus get virtualTryOnStatus => _status(_virtualTryOn);

  /// Explicit-Admin-curated Featured products (`isFeatured` + `featuredRank`).
  List<ProductSummaryModel> get featuredProducts => _featured;

  /// `ready` only when at least one product is genuinely featured — the
  /// section is hidden otherwise (no editorial fallback).
  HomeSectionStatus get featuredStatus =>
      _featured.isEmpty ? HomeSectionStatus.empty : HomeSectionStatus.ready;

  /// All featured ids in `featuredRank` order (capped) for the "See all"
  /// ordered-`productIds` Explore preset.
  List<String> get featuredSeeAllIds => _featuredSeeAllIds;

  // ── Best Sellers (productStats.unitsSold) with rating fallback ───────────
  List<ProductSummaryModel> _bestSellers = const [];
  bool _bestSellersFromSales = false;
  List<String> _bestSellersSeeAllIds = const [];

  List<ProductSummaryModel> get bestSellers => _bestSellers;
  HomeSectionStatus get bestSellersStatus => _status(_bestSellers);

  /// `true` when the section is backed by genuine `unitsSold > 0` data → the
  /// View shows **"Best Sellers"**. `false` → the honest rating fallback →
  /// the View shows **"Top Rated"**.
  bool get bestSellersUsesRealSalesData => _bestSellersFromSales;
  List<String> get bestSellersSeeAllIds => _bestSellersSeeAllIds;

  // ── Popular Furniture & Decor (productStats.favoriteCount) + fallback ────
  List<ProductSummaryModel> _popular = const [];
  bool _popularFromFavorites = false;
  List<String> _popularSeeAllIds = const [];

  List<ProductSummaryModel> get popularFurnitureDecor => _popular;
  HomeSectionStatus get popularFurnitureDecorStatus => _status(_popular);

  /// `true` when backed by genuine `favoriteCount > 0` → **"Popular Furniture
  /// & Decor"**. `false` → the rating fallback → **"Top Rated Furniture &
  /// Decor"**.
  bool get popularUsesRealFavoriteData => _popularFromFavorites;
  List<String> get popularSeeAllIds => _popularSeeAllIds;

  // ── Recently Viewed (users/{uid}/recentlyViewed) ────────────────────────
  List<String> _recentlyViewedIds = const [];
  bool _recentlyViewedLoaded = false;
  List<ProductSummaryModel> _recentlyViewedProducts = const [];
  int _recentlyViewedEligibleCount = 0;

  List<ProductSummaryModel> get recentlyViewedProducts =>
      _recentlyViewedProducts;

  /// `ready` only when the resolved, eligible history has at least one
  /// product. `loading` before the first read resolves; `empty` (hidden)
  /// once it has resolved to nothing — including on a swallowed read error.
  HomeSectionStatus get recentlyViewedStatus {
    if (_recentlyViewedProducts.isNotEmpty) return HomeSectionStatus.ready;
    return _recentlyViewedLoaded
        ? HomeSectionStatus.empty
        : HomeSectionStatus.loading;
  }

  /// "See all" (→ the dedicated `/recently-viewed` page) is offered only
  /// when more than [_sectionLimit] eligible items exist.
  bool get recentlyViewedHasSeeAll =>
      _recentlyViewedEligibleCount > _sectionLimit;

  // ── raw async signals (kept so [_recomputeSections] can re-resolve them
  //    against the cache on every catalogue change) ─────────────────────────
  List<ProductStatRank> _unitsSoldRanks = const [];
  List<ProductStatRank> _favoriteCountRanks = const [];

  // ── whole-screen error gate (preserves the Phase 9.3 pre-work behaviour) ─
  /// The one async failure surface. Stats / view-history failures never set
  /// this — they fall back or hide silently.
  bool get hasError => _categoriesStatus == HomeSectionStatus.error;

  bool get _allProductSectionsEmpty =>
      _newArrivals.isEmpty &&
      _arEnabled.isEmpty &&
      _virtualTryOn.isEmpty &&
      _bestSellers.isEmpty &&
      _popular.isEmpty &&
      _featured.isEmpty &&
      _recentlyViewedProducts.isEmpty;

  /// `true` when Categories failed AND there is genuinely nothing else to
  /// show — the only case that warrants the full-screen error + Retry
  /// (mirrors the physically-passed `hasError && isEmpty` gate).
  bool get showFullScreenError =>
      _firstLoadComplete &&
      hasError &&
      _categories.isEmpty &&
      _allProductSectionsEmpty;

  /// Retained name for API/back-compat: `true` only in the full-screen-error
  /// scenario.
  bool get isEmpty =>
      _banners.isEmpty && _categories.isEmpty && _allProductSectionsEmpty;

  // ── shopping-state passthrough (unchanged) ───────────────────────────────
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
      // Fallback
      return await _shoppingState.addToCart(productId);
    }
  }

  int _extractPriceAmount(String currentPrice) {
    final rawString = currentPrice.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(rawString) ?? 0;
  }

  // ── loading ──────────────────────────────────────────────────────────────
  /// Loads the static banners + the async Categories section (only on the
  /// first load or a forced reload), always refreshes the dynamic
  /// stats/history data, then (re)derives every product section.
  Future<void> loadHomeData({bool force = false}) async {
    if (_loadInFlight) return;
    _loadInFlight = true;
    final loadStaticSections = !_firstLoadComplete || force;
    if (!_firstLoadComplete) notifyListeners();

    if (loadStaticSections) {
      try {
        _banners = await _repository.getBanners();
      } catch (e) {
        debugPrint('Home: banners failed to load: $e');
      }
      await _loadCategories();
    }

    await Future.wait([_loadStats(), _loadRecentlyViewed()]);

    _recomputeSections();
    _firstLoadComplete = true;
    _loadInFlight = false;
    notifyListeners();
  }

  /// Re-pulls just the view-history + stats signals and re-derives the
  /// sections that depend on them. Cheap; used when Home is returned to from
  /// a pushed screen (e.g. Product Details) so a just-viewed product appears.
  Future<void> reloadDynamicSections() async {
    if (_loadInFlight) return;
    await Future.wait([_loadStats(), _loadRecentlyViewed()]);
    _recomputeSections();
    notifyListeners();
  }

  Future<void> _loadCategories() async {
    try {
      final cats = await _repository.getCategories();
      _categories = cats;
      _categoriesStatus = cats.isEmpty
          ? HomeSectionStatus.empty
          : HomeSectionStatus.ready;
    } catch (e) {
      debugPrint('Home: categories failed to load: $e');
      _categoriesStatus = HomeSectionStatus.error; // keep last-good list
    }
  }

  Future<void> _loadStats() async {
    try {
      final results = await Future.wait([
        _productStats.topByUnitsSold(limit: _seeAllLimit),
        _productStats.topByFavoriteCount(limit: _seeAllLimit),
      ]);
      _unitsSoldRanks = results[0];
      _favoriteCountRanks = results[1];
    } catch (e) {
      // The repository is contracted to swallow to `[]`; this is pure
      // defence in depth. Keep the last-good ranks and fall back silently.
      debugPrint('Home: productStats read failed (using rating fallback): $e');
    }
  }

  Future<void> _loadRecentlyViewed() async {
    try {
      _recentlyViewedIds = await _recentlyViewed.recentProductIds(
        limit: _seeAllLimit,
      );
    } catch (e) {
      // A view history that fails to load must never surface — keep whatever
      // was last resolved (empty on a first failure → the section hides).
      debugPrint('Home: recentlyViewed read failed: $e');
    }
    _recentlyViewedLoaded = true;
  }

  /// Retry just the Categories section (inline strip). The product sections
  /// are unaffected.
  Future<void> retryCategories() async {
    if (_categoriesStatus == HomeSectionStatus.loading) return;
    _categoriesStatus = HomeSectionStatus.loading;
    notifyListeners();
    await _loadCategories();
    notifyListeners();
  }

  /// Retry from the full-screen error state.
  Future<void> retry() => loadHomeData(force: true);

  Future<void> refresh() async {
    try {
      await _repository.refresh();
    } catch (e) {
      debugPrint('Home: refresh failed: $e');
    }
    await loadHomeData(force: true);
  }

  // ── derivation from the catalogue cache ──────────────────────────────────
  void _recomputeSections() {
    final eligible = _db.products.where(_isEligible).toList();
    final byId = {for (final p in eligible) p.id: p};

    _newArrivals = _pick(
      eligible.where((p) => p.addedDate.millisecondsSinceEpoch > 0),
      _byNewest,
    );
    _arEnabled = _pick(
      eligible.where((p) => p.hasRenderableArModel),
      _byNewest,
    );
    _virtualTryOn = _pick(
      eligible.where((p) => p.hasRenderableVtoAsset),
      _byNewest,
    );

    // Featured — explicit Admin curation, hidden when empty.
    final featured = eligible.where((p) => p.isFeatured).toList()
      ..sort(_byFeaturedRank);
    _featured = featured
        .take(_sectionLimit)
        .map((p) => p.toSummaryModel())
        .toList(growable: false);
    _featuredSeeAllIds = featured
        .take(_seeAllLimit)
        .map((p) => p.id)
        .toList(growable: false);

    _recomputeBestSellers(eligible, byId);
    _recomputePopular(eligible, byId);
    _recomputeRecentlyViewed(byId);
  }

  void _recomputeBestSellers(
    List<ProductModel> eligible,
    Map<String, ProductModel> byId,
  ) {
    final ranked = _resolveRanks(_unitsSoldRanks, byId);
    if (ranked.isNotEmpty) {
      _bestSellersFromSales = true;
      _bestSellers = ranked
          .take(_sectionLimit)
          .map((p) => p.toSummaryModel())
          .toList(growable: false);
      _bestSellersSeeAllIds = ranked
          .take(_seeAllLimit)
          .map((p) => p.id)
          .toList(growable: false);
      return;
    }
    _bestSellersFromSales = false;
    final rated = eligible.toList()..sort(_byRating);
    _bestSellers = rated
        .take(_sectionLimit)
        .map((p) => p.toSummaryModel())
        .toList(growable: false);
    _bestSellersSeeAllIds = rated
        .take(_seeAllLimit)
        .map((p) => p.id)
        .toList(growable: false);
  }

  void _recomputePopular(
    List<ProductModel> eligible,
    Map<String, ProductModel> byId,
  ) {
    final ranked = _resolveRanks(
      _favoriteCountRanks,
      byId,
    ).where(_isFurnitureOrDecor).toList();
    if (ranked.isNotEmpty) {
      _popularFromFavorites = true;
      _popular = ranked
          .take(_sectionLimit)
          .map((p) => p.toSummaryModel())
          .toList(growable: false);
      _popularSeeAllIds = ranked
          .take(_seeAllLimit)
          .map((p) => p.id)
          .toList(growable: false);
      return;
    }
    _popularFromFavorites = false;
    final rated = eligible.where(_isFurnitureOrDecor).toList()..sort(_byRating);
    _popular = rated
        .take(_sectionLimit)
        .map((p) => p.toSummaryModel())
        .toList(growable: false);
    _popularSeeAllIds = rated
        .take(_seeAllLimit)
        .map((p) => p.id)
        .toList(growable: false);
  }

  void _recomputeRecentlyViewed(Map<String, ProductModel> byId) {
    final seen = <String>{};
    final resolved = <ProductModel>[];
    for (final id in _recentlyViewedIds) {
      if (!seen.add(id)) continue; // dedup, keep first (newest) occurrence
      final product = byId[id];
      if (product != null) resolved.add(product);
    }
    _recentlyViewedEligibleCount = resolved.length;
    _recentlyViewedProducts = resolved
        .take(_sectionLimit)
        .map((p) => p.toSummaryModel())
        .toList(growable: false);
  }

  static bool _isEligible(ProductModel p) =>
      p.isActive && p.publicationStatus == ProductPublicationStatus.published;

  static bool _isFurnitureOrDecor(ProductModel p) =>
      p.categoryKind == ProductCategory.furniture ||
      p.categoryKind == ProductCategory.decor;

  /// Ranked list → the matching [ProductModel]s **in rank order**, silently
  /// dropping any id no longer in the eligible catalogue cache.
  static List<ProductModel> _resolveRanks(
    List<ProductStatRank> ranks,
    Map<String, ProductModel> byId,
  ) {
    final out = <ProductModel>[];
    for (final rank in ranks) {
      final product = byId[rank.productId];
      if (product != null) out.add(product);
    }
    return out;
  }

  static List<ProductSummaryModel> _pick(
    Iterable<ProductModel> src,
    Comparator<ProductModel> compare,
  ) {
    final list = src.toList()..sort(compare);
    return list
        .take(_sectionLimit)
        .map((p) => p.toSummaryModel())
        .toList(growable: false);
  }

  /// Newest genuine `addedDate` first; stable `id` tie-break.
  static int _byNewest(ProductModel a, ProductModel b) {
    final d = b.addedDate.compareTo(a.addedDate);
    return d != 0 ? d : a.id.compareTo(b.id);
  }

  /// Highest rating, then most reviews, then stable `id` — a deterministic,
  /// truthful editorial ranking (NOT a sales/popularity claim).
  static int _byRating(ProductModel a, ProductModel b) {
    final r = b.rating.compareTo(a.rating);
    if (r != 0) return r;
    final rc = b.reviewCount.compareTo(a.reviewCount);
    if (rc != 0) return rc;
    return a.id.compareTo(b.id);
  }

  /// Lowest `featuredRank` first; then newest; then stable `id`.
  static int _byFeaturedRank(ProductModel a, ProductModel b) {
    final r = a.featuredRank.compareTo(b.featuredRank);
    if (r != 0) return r;
    final d = b.addedDate.compareTo(a.addedDate);
    return d != 0 ? d : a.id.compareTo(b.id);
  }
}
