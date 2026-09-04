// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../../explore/models/catalog_product_model.dart';

class FavoritesViewModel extends ChangeNotifier {
  final CustomerShoppingState _shoppingState;
  final ProductDetailsRepository _repository;

  FavoritesViewModel({
    required CustomerShoppingState shoppingState,
    required ProductDetailsRepository repository,
  }) : _shoppingState = shoppingState,
       _repository = repository {
    _shoppingState.addListener(_onShoppingStateChanged);
    _loadFavorites();
  }

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  List<CatalogProductModel> _favoriteProducts = [];
  List<CatalogProductModel> get favoriteProducts => _favoriteProducts;

  @override
  void dispose() {
    _shoppingState.removeListener(_onShoppingStateChanged);
    super.dispose();
  }

  void _onShoppingStateChanged() {
    // If a product was removed from favorites, we can just filter our local list
    // to avoid a full reload, which makes the UI reactive and snappy.
    final currentFavoriteIds = _shoppingState.favoriteProductIds;
    bool needsUpdate = false;

    // Remove products that are no longer favorites
    final newProducts = _favoriteProducts.where((p) {
      return currentFavoriteIds.contains(p.summary.id);
    }).toList();

    if (newProducts.length != _favoriteProducts.length) {
      _favoriteProducts = newProducts;
      needsUpdate = true;
    }

    // Check if new favorites were added that we don't have loaded yet
    final loadedIds = _favoriteProducts.map((p) => p.summary.id).toSet();
    final missingIds = currentFavoriteIds.difference(loadedIds);

    if (missingIds.isNotEmpty) {
      _loadMissingFavorites(missingIds);
    } else if (needsUpdate) {
      notifyListeners();
    }
  }

  Future<void> _loadFavorites() async {
    final currentFavoriteIds = _shoppingState.favoriteProductIds;
    if (currentFavoriteIds.isEmpty) {
      _favoriteProducts = [];
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    // Phase 8.10 fix: one deleted/unpublished/otherwise-unresolvable
    // favorite must never block the rest from loading. The previous
    // `Future.wait(ids.map(repository.getProductDetails))` rejected the
    // ENTIRE batch the instant a single lookup threw, silently leaving
    // every other (perfectly resolvable) favorite unrendered too. Each
    // lookup's failure is now caught individually and simply excluded -
    // never automatically un-favorited, since a lookup failure could be
    // transient (offline), not proof the product is really gone.
    final products = await _resolveProducts(currentFavoriteIds);

    _favoriteProducts = products;
    _isLoading = false;
    notifyListeners();
  }

  Future<void> _loadMissingFavorites(Set<String> missingIds) async {
    final products = await _resolveProducts(missingIds);
    if (products.isEmpty) return;
    _favoriteProducts = [..._favoriteProducts, ...products];
    notifyListeners();
  }

  Future<List<CatalogProductModel>> _resolveProducts(Set<String> ids) async {
    final results = await Future.wait(
      ids.map((id) async {
        try {
          final detail = await _repository.getProductDetails(id);
          return CatalogProductModel(
            summary: detail.summary,
            categoryId: detail.categoryId,
            categoryKind: detail.categoryKind,
            priceAmount: _extractPriceAmount(detail.summary.currentPrice),
            sizes: detail.availableSizes.toSet(),
            colors: detail.availableColors.toSet(),
            addedDate: DateTime.now(),
          );
        } catch (e) {
          debugPrint('Failed to resolve favorite product $id: $e');
          return null;
        }
      }),
    );
    return results.whereType<CatalogProductModel>().toList();
  }

  int _extractPriceAmount(String currentPrice) {
    // "Rs 12,000/-" -> 12000
    final rawString = currentPrice.replaceAll(RegExp(r'[^0-9]'), '');
    return int.tryParse(rawString) ?? 0;
  }

  bool isFavorite(String productId) => _shoppingState.isFavorite(productId);

  /// Returns `null` on success or a clean, `AppToast`-ready error message.
  Future<String?> toggleFavorite(String productId) =>
      _shoppingState.toggleFavorite(productId);

  Future<String?> addToCart(String productId) async {
    try {
      final details = await _repository.getProductDetails(productId);
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
}
