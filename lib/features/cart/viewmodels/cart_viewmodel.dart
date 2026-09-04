import 'package:flutter/foundation.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../models/cart_item_model.dart';
import '../models/populated_cart_item.dart';
import '../../../core/constants/pricing_constants.dart';

class CartViewModel extends ChangeNotifier {
  final CustomerShoppingState _shoppingState;
  final ProductDetailsRepository _productRepository;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  List<PopulatedCartItem> _populatedItems = [];
  List<PopulatedCartItem> get populatedItems => _populatedItems;

  /// Cart lines whose product could not be resolved (deleted/unpublished/
  /// transient lookup failure) - Phase 8.10 requirement: one unresolvable
  /// product must never crash or block the rest of the cart, and must never
  /// be silently auto-removed just because a lookup temporarily failed.
  /// Rendered as a minimal removable row so the customer can clear it
  /// themselves if it's really gone.
  List<CartItemModel> _unavailableItems = [];
  List<CartItemModel> get unavailableItems => _unavailableItems;
  bool get hasUnavailableItems => _unavailableItems.isNotEmpty;

  /// Phase 8.11a - per cart line ([CartItemModel.id] -> message) for lines
  /// whose product resolved fine but is out of stock, or whose combined
  /// requested quantity (aggregated across every variant of the same
  /// `productId`) exceeds the product's current stock. Rendered as a small
  /// inline warning on the affected cart item; also blocks
  /// "Proceed to Checkout" (see [validateForCheckout]). The item is never
  /// auto-removed - the customer reduces the quantity or removes it.
  Map<String, String> _stockIssues = {};
  bool get hasStockIssues => _stockIssues.isNotEmpty;
  String? stockIssueFor(String cartItemId) => _stockIssues[cartItemId];

  double get deliveryFee => PricingConstants.deliveryFee;
  double get discount => PricingConstants.discount;

  double get subtotal {
    double total = 0.0;
    for (var item in _populatedItems) {
      final priceStr = item.product.summary.currentPrice.replaceAll(
        RegExp(r'[^0-9.]'),
        '',
      );
      final price = double.tryParse(priceStr) ?? 0.0;
      total += price * item.cartItem.quantity;
    }
    return total;
  }

  double get total {
    double calculatedTotal = subtotal + deliveryFee - discount;
    return calculatedTotal > 0 ? calculatedTotal : 0.0;
  }

  CartViewModel(this._shoppingState, this._productRepository) {
    _shoppingState.addListener(_onShoppingStateChanged);
    _loadCartProducts();
  }

  @override
  void dispose() {
    _shoppingState.removeListener(_onShoppingStateChanged);
    super.dispose();
  }

  void _onShoppingStateChanged() {
    _loadCartProducts();
  }

  /// Phase 8.10 fix: resolves each cart line's product INDEPENDENTLY (never
  /// a single `Future.wait`/loop that aborts the whole cart the instant one
  /// line's product fails to resolve). A failure isolates that one line into
  /// [unavailableItems] instead of hiding every other, perfectly-resolvable
  /// line behind a single generic error.
  Future<void> _loadCartProducts() async {
    final cartItems = _shoppingState.cartItems;
    if (cartItems.isEmpty) {
      _populatedItems = [];
      _unavailableItems = [];
      _stockIssues = {};
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    final populated = <PopulatedCartItem>[];
    final unavailable = <CartItemModel>[];

    for (final cartItem in cartItems) {
      try {
        final productDetails = await _productRepository.getProductDetails(
          cartItem.productId,
        );
        populated.add(PopulatedCartItem(cartItem, productDetails));
      } catch (e) {
        debugPrint('Cart item ${cartItem.productId} could not be resolved: $e');
        unavailable.add(cartItem);
      }
    }

    _populatedItems = populated;
    _unavailableItems = unavailable;
    _stockIssues = _computeStockIssues(populated);
    _isLoading = false;
    notifyListeners();
  }

  /// Aggregates requested quantities by `productId` (so different colour/size
  /// variants of the same product count together) and flags every line whose
  /// product is out of stock, or whose product's combined requested quantity
  /// exceeds its current stock.
  Map<String, String> _computeStockIssues(List<PopulatedCartItem> populated) {
    final requestedByProductId = <String, int>{};
    for (final item in populated) {
      requestedByProductId.update(
        item.cartItem.productId,
        (existing) => existing + item.cartItem.quantity,
        ifAbsent: () => item.cartItem.quantity,
      );
    }

    final issues = <String, String>{};
    for (final item in populated) {
      final stock = item.product.stockQuantity;
      final requested = requestedByProductId[item.cartItem.productId] ?? 0;
      if (stock <= 0) {
        issues[item.cartItem.id] = 'Out of stock';
      } else if (requested > stock) {
        issues[item.cartItem.id] = 'Only $stock available';
      }
    }
    return issues;
  }

  /// Re-resolves current product data and re-checks every cart line before
  /// the customer leaves the cart. Returns `null` when checkout may proceed,
  /// or a clean, `AppToast`-ready message when it must not. The affected
  /// lines are reflected in [stockIssueFor] / [unavailableItems] so the UI
  /// can also mark them inline. Nothing is removed from the cart.
  Future<String?> validateForCheckout() async {
    await _loadCartProducts();
    if (_populatedItems.isEmpty && !hasUnavailableItems) {
      return 'Your cart is empty.';
    }
    if (hasUnavailableItems) {
      return 'Some items are no longer available. Please remove them to continue.';
    }
    if (hasStockIssues) {
      return 'Some items are out of stock or exceed the available quantity. Please update your cart.';
    }
    return null;
  }

  /// Returns `null` on success or a clean, `AppToast`-ready error message.
  Future<String?> updateQuantity(String cartItemId, int newQuantity) =>
      _shoppingState.updateQuantity(cartItemId, newQuantity);

  Future<String?> removeFromCart(String cartItemId) =>
      _shoppingState.removeFromCart(cartItemId);
}
