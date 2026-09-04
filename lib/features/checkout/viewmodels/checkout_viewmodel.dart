import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import '../../../app/viewmodels/customer_address_state.dart';
import '../../../app/viewmodels/customer_order_state.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/constants/pricing_constants.dart';
import '../../address/models/address_model.dart';
import '../../cart/models/cart_item_model.dart';
import '../../cart/models/populated_cart_item.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../models/checkout_payment_models.dart';
import '../services/checkout_cart_reconciler.dart';
import '../services/checkout_idempotency.dart';
import '../services/checkout_payment_service.dart';

/// Where the checkout screen is in the Phase 8.13.5 Stripe flow.
enum CheckoutPhase {
  /// Ready to pay (or after a recoverable error - the cart is untouched).
  idle,

  /// Calling `createPaymentIntent` (reserving stock server-side).
  reserving,

  /// Stripe PaymentSheet is open.
  presenting,

  /// PaymentSheet closed with the payment submitted - waiting for the webhook
  /// to mark the session `succeeded` and create the real order. NOT success.
  finalizing,

  /// The webhook is taking unusually long. The payment was submitted; the
  /// customer must not pay again. The order will appear in My Orders.
  processingTimeout,

  /// The webhook confirmed the order. The View navigates to Order Result.
  succeeded,

  /// The publishable key was not built in - card payment is unavailable.
  paymentUnavailable,
}

/// Drives the checkout screen. The old fake "write an order client-side" flow
/// is gone: this ViewModel only ever CALLS the server and READS the
/// authoritative `checkoutSessions/{id}` result. It never writes a
/// checkout-session, stock, order or payment document.
class CheckoutViewModel extends ChangeNotifier {
  final CustomerShoppingState _shoppingState;
  final CustomerAddressState _addressState;
  final ProductDetailsRepository _productRepository;
  final AuthSessionState _authSessionState;
  final CheckoutPaymentService _paymentService;
  final CustomerOrderState _orderState;

  /// How long to wait for the webhook before showing the "still processing"
  /// state. Kept generous - webhooks are normally < 5s.
  final Duration finalizeTimeout;

  bool _disposed = false;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  CheckoutPhase _phase = CheckoutPhase.idle;
  CheckoutPhase get phase => _phase;

  /// `true` while a payment attempt is actively in flight - the View disables
  /// the pay button and blocks back-navigation.
  bool get isBusy =>
      _phase == CheckoutPhase.reserving ||
      _phase == CheckoutPhase.presenting ||
      _phase == CheckoutPhase.finalizing;

  String? _error;
  String? get error => _error;

  /// The kind of the most recent error - lets the View pick an info vs error
  /// toast (a user cancel is not an error).
  CheckoutErrorKind? _lastErrorKind;
  CheckoutErrorKind? get lastErrorKind => _lastErrorKind;

  String? _succeededOrderId;
  String? get succeededOrderId => _succeededOrderId;

  List<PopulatedCartItem> _populatedItems = [];
  List<PopulatedCartItem> get populatedItems => _populatedItems;

  List<CartItemModel> _unavailableItems = [];
  List<CartItemModel> get unavailableItems => _unavailableItems;
  bool get hasUnavailableItems => _unavailableItems.isNotEmpty;

  AddressModel? get selectedAddress => _addressState.selectedAddress;
  bool get isEmptyCart => _shoppingState.cartItems.isEmpty;
  bool get isMissingAddress => _addressState.selectedAddress == null;
  int get totalItems => _shoppingState.cartCount;

  /// One stable key per checkout attempt (reused across cancel / decline /
  /// re-present); a NEW key is minted only once the prior attempt is terminal.
  String _idempotencyKey = generateCheckoutIdempotencyKey();

  /// Server-authoritative totals from `createPaymentIntent` / the session doc.
  /// Once set, these are what the price summary shows.
  CheckoutTotals? _serverTotals;

  /// The exact cart lines this attempt is paying for, frozen at
  /// [startCheckout] time. On confirmed success ONLY these are removed from
  /// the cart - anything the customer adds during a slow finalize is kept.
  List<PurchasedLine> _purchasedLines = const [];

  StreamSubscription<CheckoutSessionUpdate>? _sessionSub;
  Timer? _finalizeTimer;

  CheckoutViewModel(
    this._shoppingState,
    this._addressState,
    this._productRepository,
    this._authSessionState,
    this._paymentService,
    this._orderState, {
    this.finalizeTimeout = const Duration(seconds: 45),
  }) {
    _shoppingState.addListener(_onStateChanged);
    _addressState.addListener(_onStateChanged);
    if (!_paymentService.isConfigured) {
      _phase = CheckoutPhase.paymentUnavailable;
    }
    _loadCartProducts();
  }

  @override
  void dispose() {
    _disposed = true;
    _sessionSub?.cancel();
    _finalizeTimer?.cancel();
    _shoppingState.removeListener(_onStateChanged);
    _addressState.removeListener(_onStateChanged);
    super.dispose();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  void _onStateChanged() {
    // Cart / address edits only matter before a payment attempt is in flight.
    if (isBusy || _phase == CheckoutPhase.succeeded) return;
    _loadCartProducts();
  }

  // --- price summary (server totals win once known) --------------------------

  double get deliveryFee =>
      (_serverTotals?.deliveryFee ?? PricingConstants.deliveryFee).toDouble();
  double get discount =>
      (_serverTotals?.discount ?? PricingConstants.discount).toDouble();

  double get subtotal {
    final server = _serverTotals;
    if (server != null) return server.subtotal.toDouble();
    double sum = 0.0;
    for (final item in _populatedItems) {
      final priceStr = item.product.summary.currentPrice.replaceAll(
        RegExp(r'[^0-9.]'),
        '',
      );
      sum += (double.tryParse(priceStr) ?? 0.0) * item.cartItem.quantity;
    }
    return sum;
  }

  double get total {
    final server = _serverTotals;
    if (server != null) return server.total.toDouble();
    final t = subtotal + deliveryFee - discount;
    return t > 0 ? t : 0.0;
  }

  // --- cart load ------------------------------------------------------------

  Future<void> _loadCartProducts() async {
    final cartItems = _shoppingState.cartItems;
    if (cartItems.isEmpty) {
      _populatedItems = [];
      _unavailableItems = [];
      if (_phase != CheckoutPhase.paymentUnavailable) _error = null;
      _notify();
      return;
    }

    _isLoading = true;
    _notify();

    final populated = <PopulatedCartItem>[];
    final unavailable = <CartItemModel>[];
    for (final cartItem in cartItems) {
      try {
        final productDetails = await _productRepository.getProductDetails(
          cartItem.productId,
        );
        populated.add(PopulatedCartItem(cartItem, productDetails));
      } catch (_) {
        unavailable.add(cartItem);
      }
    }

    if (_disposed) return;
    _populatedItems = populated;
    _unavailableItems = unavailable;
    _isLoading = false;
    _notify();
  }

  /// Persistent inline warning for the checkout screen when a cart line can no
  /// longer be resolved (deleted / unpublished product). Not a toast.
  String? get unavailableItemsMessage => _unavailableItems.isEmpty
      ? null
      : 'Some items in your cart are no longer available. Please go back to your cart to review them.';

  // --- the checkout flow --------------------------------------------------

  /// Kick off (or retry) a Stripe checkout attempt. Re-entrant taps while a
  /// payment is in flight are ignored.
  Future<void> startCheckout() async {
    if (isBusy ||
        _phase == CheckoutPhase.succeeded ||
        _phase == CheckoutPhase.processingTimeout) {
      return;
    }

    if (!_paymentService.isConfigured) {
      _phase = CheckoutPhase.paymentUnavailable;
      _setError(
        CheckoutErrorKind.notConfigured,
        'Card payment is temporarily unavailable. Please try again later.',
      );
      return;
    }
    if (isEmptyCart) {
      _setIdleError(CheckoutErrorKind.unknown, 'Your cart is empty.');
      return;
    }
    if (hasUnavailableItems) {
      _setIdleError(
        CheckoutErrorKind.productUnavailable,
        'Some items in your cart are no longer available. Please go back to your cart to review them.',
      );
      return;
    }
    final address = _addressState.selectedAddress;
    if (address == null || address.id.isEmpty) {
      _setIdleError(
        CheckoutErrorKind.addressProblem,
        'Please choose a delivery address.',
      );
      return;
    }
    if (_authSessionState.userId == null) {
      _setIdleError(
        CheckoutErrorKind.unknown,
        'Please sign in again to place your order.',
      );
      return;
    }

    _error = null;
    _lastErrorKind = null;
    _phase = CheckoutPhase.reserving;
    _notify();

    final items = _populatedItems
        .map(
          (p) => CheckoutLineItemRequest(
            productId: p.cartItem.productId,
            quantity: p.cartItem.quantity,
            selectedColor: p.cartItem.selectedColor?.name,
            selectedSize: p.cartItem.selectedSize?.name,
          ),
        )
        .toList();

    // Freeze what this attempt is buying, so a slow finalize + a later cart
    // add never causes the new item to be cleared on success.
    _purchasedLines = _populatedItems
        .map(
          (p) => PurchasedLine(
            productId: p.cartItem.productId,
            quantity: p.cartItem.quantity,
            selectedColor: p.cartItem.selectedColor?.name,
            selectedSize: p.cartItem.selectedSize?.name,
          ),
        )
        .toList();

    final CreatePaymentIntentResult reservation;
    try {
      reservation = await _paymentService.createPaymentIntent(
        items: items,
        addressId: address.id,
        idempotencyKey: _idempotencyKey,
      );
    } on CheckoutPaymentException catch (e) {
      _handlePaymentError(e);
      return;
    }
    if (_disposed) return;

    _serverTotals = reservation.totals;
    _phase = CheckoutPhase.presenting;
    _notify();

    try {
      await _paymentService.presentPaymentSheet(
        clientSecret: reservation.paymentIntentClientSecret,
      );
    } on CheckoutPaymentException catch (e) {
      _handlePaymentError(e);
      return;
    }
    if (_disposed) return;

    // PaymentSheet returned with the payment SUBMITTED. Not success - wait
    // for the webhook.
    _phase = CheckoutPhase.finalizing;
    _notify();
    _listenForFinalization(reservation.checkoutSessionId);
  }

  void _listenForFinalization(String sessionId) {
    _sessionSub?.cancel();
    _finalizeTimer?.cancel();
    _sessionSub = _paymentService
        .watchSession(sessionId)
        .listen(
          _onSessionUpdate,
          onError: (_) {
            // A transient listener error does not mean the order failed - the
            // webhook may still be finalizing it. Keep waiting; the timer is the
            // backstop.
          },
        );
    _finalizeTimer = Timer(finalizeTimeout, _onFinalizeTimeout);
  }

  Future<void> _onSessionUpdate(CheckoutSessionUpdate update) async {
    if (_disposed) return;
    if (_phase != CheckoutPhase.finalizing &&
        _phase != CheckoutPhase.processingTimeout) {
      return;
    }
    if (update.totals != null) _serverTotals = update.totals;

    if (update.isSucceededWithOrder) {
      await _completeSuccess(update.orderId!);
      return;
    }
    if (update.isTerminalFailure) {
      _cancelFinalization();
      _startFreshAttempt();
      _setIdleError(
        CheckoutErrorKind.cardDeclined,
        'Your payment could not be completed and no charge was kept. Please try again.',
      );
    }
  }

  Future<void> _completeSuccess(String orderId) async {
    _cancelFinalization();
    // Give the customer's own `orders` listener a moment to surface the new
    // order so Order Result renders it right away (it still self-heals via
    // `context.watch` if this races).
    await _waitForOrderVisible(orderId, const Duration(seconds: 12));
    if (_disposed) return;
    // Remove ONLY the lines this checkout paid for - the webhook confirmed
    // the order exists. Anything added to the cart during a slow finalize is
    // preserved (see removePurchasedLinesFromCart).
    try {
      await removePurchasedLinesFromCart(_shoppingState, _purchasedLines);
    } catch (_) {
      // Best-effort: the order is real regardless of the cart update.
    }
    _succeededOrderId = orderId;
    _phase = CheckoutPhase.succeeded;
    _error = null;
    _notify();
  }

  Future<void> _waitForOrderVisible(String orderId, Duration limit) async {
    final deadline = DateTime.now().add(limit);
    while (!_disposed && DateTime.now().isBefore(deadline)) {
      if (_orderState.getOrderById(orderId) != null) return;
      await Future<void>.delayed(const Duration(milliseconds: 300));
    }
  }

  void _onFinalizeTimeout() {
    if (_disposed || _phase != CheckoutPhase.finalizing) return;
    _finalizeTimer?.cancel();
    // Keep the session listener alive - a late `succeeded` still completes the
    // order and clears the cart. We just stop showing the plain spinner and
    // tell the customer their payment went through.
    _phase = CheckoutPhase.processingTimeout;
    _notify();
  }

  void _cancelFinalization() {
    _sessionSub?.cancel();
    _sessionSub = null;
    _finalizeTimer?.cancel();
    _finalizeTimer = null;
  }

  void _handlePaymentError(CheckoutPaymentException e) {
    if (_disposed) return;
    _cancelFinalization();
    if (e.kind == CheckoutErrorKind.notConfigured) {
      _phase = CheckoutPhase.paymentUnavailable;
      _setError(e.kind, e.message);
      return;
    }
    if (e.requiresFreshAttempt) {
      _startFreshAttempt();
    }
    // A cancel / decline keeps the same idempotency key: the reservation
    // still stands, so a retry re-presents the SAME PaymentIntent.
    _setIdleError(e.kind, e.message);
  }

  void _startFreshAttempt() {
    _idempotencyKey = generateCheckoutIdempotencyKey();
    _serverTotals = null;
  }

  void _setIdleError(CheckoutErrorKind kind, String message) {
    _phase = CheckoutPhase.idle;
    _setError(kind, message);
  }

  void _setError(CheckoutErrorKind kind, String message) {
    _error = message;
    _lastErrorKind = kind;
    _notify();
  }

  /// Called by the View once it has shown [error] as a toast, so it is not
  /// shown again on the next rebuild.
  void acknowledgeError() {
    _error = null;
    _lastErrorKind = null;
  }
}
