import 'package:flutter/foundation.dart';

import '../../core/data/cart_repository.dart';
import '../../core/data/favorites_repository.dart';
import '../../features/cart/models/cart_item_model.dart';
import '../../core/models/product/product_color_option.dart';
import '../../core/models/product/product_size.dart';

/// Thin reactive wrapper around [FavoritesRepository] + [CartRepository]
/// (Phase 8.10). Kept as ONE class (not split in two) because the app's
/// ViewModels (`HomeViewModel`, `ExploreViewModel`, `FavoritesViewModel`,
/// `CartViewModel`, `ProductDetailsViewModel`, `CheckoutViewModel`) all
/// depend on a single shared "shopping state" instance today - splitting it
/// would touch every one of those call sites for no behavioral benefit.
///
/// All real Firestore complexity - uid isolation, generation-guarded stale
/// callbacks, atomic cart-quantity merge, malformed-document isolation -
/// lives entirely in the two repositories' real implementations
/// (`FirestoreFavoritesRepository`/`FirestoreCartRepository`). This class
/// only adapts between their domain-tuple-based cart API and the
/// `CartItemModel.id`-based API every existing cart View/ViewModel already
/// calls, so none of that call-site code needs to change shape.
class CustomerShoppingState extends ChangeNotifier {
  final FavoritesRepository _favoritesRepository;
  final CartRepository _cartRepository;

  CustomerShoppingState(this._favoritesRepository, this._cartRepository) {
    _favoritesRepository.addListener(notifyListeners);
    _cartRepository.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _favoritesRepository.removeListener(notifyListeners);
    _cartRepository.removeListener(notifyListeners);
    super.dispose();
  }

  bool get isFavoritesLoading => _favoritesRepository.isLoading;
  bool get hasFavoritesError => _favoritesRepository.hasError;
  bool get isCartLoading => _cartRepository.isLoading;
  bool get hasCartError => _cartRepository.hasError;

  Set<String> get favoriteProductIds => _favoritesRepository.favoriteProductIds;
  List<CartItemModel> get cartItems => _cartRepository.items;

  int get cartCount => _cartRepository.itemCount;

  bool isFavorite(String productId) =>
      _favoritesRepository.isFavorite(productId);

  Future<String?> toggleFavorite(String productId) async {
    try {
      await _favoritesRepository.toggleFavorite(productId);
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  Future<String?> addToCart(
    String productId, {
    int quantity = 1,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
    int priceAmountSnapshot = 0,
  }) async {
    try {
      await _cartRepository.addItem(
        productId: productId,
        quantity: quantity,
        selectedColor: selectedColor,
        selectedSize: selectedSize,
        priceAmountSnapshot: priceAmountSnapshot,
      );
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  /// [cartItemId] is [CartItemModel.id] - the same local composite key
  /// every existing cart View/ViewModel already passes. Resolved back to
  /// its `(productId, selectedColor, selectedSize)` tuple against the
  /// currently-loaded [cartItems] before delegating to the repository.
  Future<String?> updateQuantity(String cartItemId, int newQuantity) async {
    if (newQuantity < cartMinQuantity) return null;
    final item = _findById(cartItemId);
    if (item == null) return null;
    try {
      await _cartRepository.setQuantity(
        productId: item.productId,
        selectedColor: item.selectedColor,
        selectedSize: item.selectedSize,
        quantity: newQuantity,
      );
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  Future<String?> removeFromCart(String cartItemId) async {
    final item = _findById(cartItemId);
    if (item == null) return null;
    try {
      await _cartRepository.removeItem(
        productId: item.productId,
        selectedColor: item.selectedColor,
        selectedSize: item.selectedSize,
      );
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  Future<String?> clearCart() async {
    try {
      await _cartRepository.clear();
      return null;
    } catch (e) {
      return _cleanError(e);
    }
  }

  CartItemModel? _findById(String cartItemId) {
    for (final item in cartItems) {
      if (item.id == cartItemId) return item;
    }
    return null;
  }

  String _cleanError(Object e) {
    if (e is StateError) return e.message;
    return 'Something went wrong. Please try again.';
  }
}
