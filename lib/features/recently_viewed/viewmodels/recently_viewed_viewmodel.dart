// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/data/commerce_database.dart';
import '../../../core/models/product/product_mappers.dart';
import '../../../core/models/product/product_model.dart';
import '../../../core/models/product/product_publication_status.dart';
import '../../../core/models/product/product_summary_model.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../../product_details/repositories/recently_viewed_repository.dart';

/// Backs the dedicated `/recently-viewed` page — the signed-in customer's
/// full product-view history, **newest first**, resolved against the live
/// catalogue cache (deleted / draft / unpublished / inactive products drop
/// out) and deduplicated. Recency order is the whole point, so it is never
/// re-sorted.
///
/// Reactive to catalogue changes: a product the customer viewed that an
/// Admin then unpublishes disappears from the list without a reload.
class RecentlyViewedViewModel extends ChangeNotifier {
  final RecentlyViewedRepository _repository;
  final CommerceDatabase _db;
  final CustomerShoppingState _shoppingState;
  final ProductDetailsRepository _productDetailsRepository;

  /// A generous cap — the repository already trims the collection to ~30.
  static const int _historyLimit = 60;

  RecentlyViewedViewModel({
    required RecentlyViewedRepository repository,
    required CommerceDatabase db,
    required CustomerShoppingState shoppingState,
    required ProductDetailsRepository productDetailsRepository,
  }) : _repository = repository,
       _db = db,
       _shoppingState = shoppingState,
       _productDetailsRepository = productDetailsRepository {
    _db.addListener(_onDbChanged);
    _shoppingState.addListener(_onShoppingStateChanged);
    _load();
  }

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  bool _errored = false;

  /// An error surfaces only when it left us with nothing to show — a
  /// transient failure with a resolved list still on screen stays silent.
  bool get hasError => _errored && _products.isEmpty;

  List<String> _ids = const [];
  List<ProductSummaryModel> _products = const [];
  List<ProductSummaryModel> get products => _products;

  bool get isEmpty => !_isLoading && !hasError && _products.isEmpty;

  @override
  void dispose() {
    _db.removeListener(_onDbChanged);
    _shoppingState.removeListener(_onShoppingStateChanged);
    super.dispose();
  }

  void _onDbChanged() {
    _resolve();
    notifyListeners();
  }

  void _onShoppingStateChanged() => notifyListeners();

  Future<void> _load() async {
    _isLoading = true;
    notifyListeners();
    try {
      _ids = await _repository.recentProductIds(limit: _historyLimit);
      _errored = false;
    } catch (e) {
      debugPrint('RecentlyViewed: history read failed: $e');
      _errored = true;
    }
    _resolve();
    _isLoading = false;
    notifyListeners();
  }

  Future<void> refresh() => _load();

  void _resolve() {
    final byId = {for (final p in _db.products.where(_isEligible)) p.id: p};
    final seen = <String>{};
    final out = <ProductSummaryModel>[];
    for (final id in _ids) {
      if (!seen.add(id)) continue; // dedup, keep newest occurrence
      final product = byId[id];
      if (product != null) out.add(product.toSummaryModel());
    }
    _products = out;
  }

  static bool _isEligible(ProductModel p) =>
      p.isActive && p.publicationStatus == ProductPublicationStatus.published;

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
}
