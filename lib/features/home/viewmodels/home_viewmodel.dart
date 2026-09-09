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
import '../models/category_model.dart';
import '../models/home_banner_model.dart';
import '../repositories/home_repository.dart';

/// Per-section lifecycle. Every Home section reports its own status so one
/// failing/empty section can never blank the others.
enum HomeSectionStatus { loading, ready, empty, error }

/// Phase 9.3 pre-work — "Dynamic Home Content" Stage 1
/// (`20_DYNAMIC_HOME_CONTENT_PLAN.md`).
///
/// Home now has exactly one independently-failing async section — **Shop by
/// Category** (a real `categories` collection read via [HomeRepository]). The
/// hero banners are static. Every product section is **derived synchronously
/// from the live `CommerceDatabase` customer catalogue cache** (the
/// `published && isActive` snapshot the app already maintains) — no per-
/// section network call, no hardcoded product IDs, and each recomputes for
/// free whenever the catalogue changes ([_onDbChanged]).
///
/// Interim (Stage 1) sections until their real contracts ship in Stage 2/3:
///  * `topRated` / `topRatedFurnitureDecor` — a deterministic
///    rating→reviewCount→id ranking, labelled **"Top Rated"** in the View
///    (never "Best Sellers" / "Popular" — there is no sales/engagement data
///    yet, and none is fabricated).
///  * `featuredProducts` — the pre-existing `recommendationRank == 10`
///    editorial signal, unchanged, now sourced from the cache. A real
///    Admin `isFeatured` control is Stage 2/3.
///  * Recently Viewed — **removed from Home** until its real per-customer
///    history contract exists (Stage 2/3).
class HomeViewModel extends ChangeNotifier {
  final HomeRepository _repository;
  final ProductDetailsRepository _productDetailsRepository;
  final CustomerShoppingState _shoppingState;
  final CommerceDatabase _db;

  static const int _sectionLimit = 3;

  HomeViewModel(
    this._repository,
    this._productDetailsRepository,
    this._shoppingState,
    this._db,
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
    // spinner, then re-pull the async Categories section in the background.
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
  List<ProductSummaryModel> _topRated = const [];
  List<ProductSummaryModel> _topRatedFurnitureDecor = const [];
  List<ProductSummaryModel> _featured = const [];

  List<ProductSummaryModel> get newArrivals => _newArrivals;
  HomeSectionStatus get newArrivalsStatus => _status(_newArrivals);

  List<ProductSummaryModel> get arEnabledProducts => _arEnabled;
  HomeSectionStatus get arEnabledStatus => _status(_arEnabled);

  List<ProductSummaryModel> get virtualTryOnCollection => _virtualTryOn;
  HomeSectionStatus get virtualTryOnStatus => _status(_virtualTryOn);

  /// Interim "Top Rated" — NOT "Best Sellers" (no sales data exists yet).
  List<ProductSummaryModel> get topRated => _topRated;
  HomeSectionStatus get topRatedStatus => _status(_topRated);

  /// Interim "Top Rated Furniture & Decor" — NOT "Popular".
  List<ProductSummaryModel> get topRatedFurnitureDecor =>
      _topRatedFurnitureDecor;
  HomeSectionStatus get topRatedFurnitureDecorStatus =>
      _status(_topRatedFurnitureDecor);

  List<ProductSummaryModel> get featuredProducts => _featured;
  HomeSectionStatus get featuredStatus => _status(_featured);

  // ── whole-screen error gate (preserves the Phase 9.3 pre-work behaviour) ─
  /// The one async failure surface.
  bool get hasError => _categoriesStatus == HomeSectionStatus.error;

  bool get _allProductSectionsEmpty =>
      _newArrivals.isEmpty &&
      _arEnabled.isEmpty &&
      _virtualTryOn.isEmpty &&
      _topRated.isEmpty &&
      _topRatedFurnitureDecor.isEmpty &&
      _featured.isEmpty;

  /// `true` when Categories failed AND there is genuinely nothing else to
  /// show — the only case that warrants the full-screen error + Retry
  /// (mirrors the physically-passed `hasError && isEmpty` gate, now
  /// section-aware). A single failed section with content elsewhere shows an
  /// inline retry strip instead.
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
  /// Loads the static banners and the async Categories section, then
  /// (re)derives the product sections from the catalogue cache.
  ///
  /// A Categories failure sets only [categoriesStatus] to `error` and keeps
  /// the last-good list — it never latches `_firstLoadComplete` back to
  /// `false` and never touches the product sections. `_loadInFlight`
  /// collapses the near-simultaneous `initState` + `_onDbChanged` calls.
  Future<void> loadHomeData({bool force = false}) async {
    if (_loadInFlight) return;
    if (_firstLoadComplete && !force) return;
    _loadInFlight = true;
    if (!_firstLoadComplete) notifyListeners();

    try {
      _banners = await _repository.getBanners();
    } catch (e) {
      debugPrint('Home: banners failed to load: $e');
      // Keep whatever was last good (empty on a genuine first failure).
    }

    await _loadCategories();

    _recomputeSections();
    _firstLoadComplete = true;
    _loadInFlight = false;
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
    final eligible = _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published,
        )
        .toList();

    _newArrivals = _pick(
      eligible.where((p) => p.addedDate.millisecondsSinceEpoch > 0),
      _byNewest,
    );
    _arEnabled = _pick(
      eligible.where((p) => p.hasRenderableArModel),
      _byNewest,
    );
    _virtualTryOn = _pick(
      eligible.where((p) => p.isVirtualTryOnEnabled),
      _byNewest,
    );
    _topRated = _pick(eligible, _byRating);
    _topRatedFurnitureDecor = _pick(
      eligible.where(
        (p) =>
            p.categoryKind == ProductCategory.furniture ||
            p.categoryKind == ProductCategory.decor,
      ),
      _byRating,
    );
    // Interim Featured signal — unchanged from before Stage 1.
    _featured = _pick(
      eligible.where((p) => p.recommendationRank == 10),
      _byRank,
    );
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

  static int _byRank(ProductModel a, ProductModel b) {
    final r = a.recommendationRank.compareTo(b.recommendationRank);
    return r != 0 ? r : a.id.compareTo(b.id);
  }
}
