import 'package:flutter/widgets.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../models/checkout_payment_models.dart';
import 'checkout_payment_service.dart';

/// Phase 8.13.6 - late-success cart reconciliation.
///
/// The authoritative "clear the cart" step happens only once the Stripe
/// webhook has confirmed the order and given it a real `orderId`. While the
/// checkout screen is open, [CheckoutViewModel] does that itself (it keeps
/// the `checkoutSessions/{id}` listener alive even through the
/// "still processing" state). But if the customer closed the screen before
/// the webhook (or the scheduled sweep) finalized a genuinely-paid session,
/// the ViewModel is gone and never got to remove the purchased lines - the
/// order lands in My Orders but the cart still shows those items.
///
/// This app-level reconciler closes that gap. On sign-in and on app resume
/// it asks [CheckoutPaymentService] for the customer's recently-`succeeded`
/// checkout sessions and removes exactly the `(productId, colour, size)`
/// lines those checkouts purchased - reducing the quantity when the customer
/// has since added more of the same variant, and never touching a line for
/// any product/variant that was not part of a completed checkout.
///
/// It only ever READS `checkoutSessions` and mutates the cart; it never
/// writes a checkout-session, stock, order or payment document.
class CheckoutCartReconciler with WidgetsBindingObserver {
  final CheckoutPaymentService _paymentService;
  final CustomerShoppingState _shopping;
  final AuthSessionState _auth;

  bool _running = false;
  bool _disposed = false;
  String? _lastReconciledUid;

  CheckoutCartReconciler(this._paymentService, this._shopping, this._auth) {
    _auth.addListener(_onAuthChanged);
    WidgetsBinding.instance.addObserver(this);
    // Kick off once for the session that may already be signed in.
    _maybeReconcile();
  }

  void _onAuthChanged() {
    // A fresh sign-in (or account switch) should re-run once.
    if (_auth.userId != _lastReconciledUid) _maybeReconcile();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _maybeReconcile();
  }

  /// Runs the reconciliation now. Public so it can be driven directly from a
  /// test; safe to call repeatedly (re-entrant calls are ignored).
  Future<void> reconcileNow() => _maybeReconcile();

  Future<void> _maybeReconcile() async {
    if (_disposed || _running) return;
    if (!_paymentService.isConfigured) return;
    final uid = _auth.userId;
    if (uid == null || uid.isEmpty) return;

    _running = true;
    try {
      final purchased = await _paymentService.recentlyPurchasedLines(uid);
      if (_disposed) return;
      if (purchased.isNotEmpty) {
        await removePurchasedLinesFromCart(_shopping, purchased);
      }
      _lastReconciledUid = uid;
    } catch (_) {
      // Best-effort - a later resume / sign-in will try again.
    } finally {
      _running = false;
    }
  }

  void dispose() {
    _disposed = true;
    _auth.removeListener(_onAuthChanged);
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// Removes each purchased line from the cart, matched on
/// `(productId, colour name, size name)`:
///
///  * cart quantity <= purchased quantity  -> the line is removed entirely;
///  * cart quantity  > purchased quantity  -> the line is reduced by the
///    purchased quantity (the customer added more of the same variant after
///    checking out, so the extra is kept);
///  * no matching cart line                -> nothing happens.
///
/// A cart line for any product/variant that is not in [purchased] is never
/// touched. Shared by [CheckoutCartReconciler] and [CheckoutViewModel] so
/// both the in-session and screen-closed paths behave identically.
Future<void> removePurchasedLinesFromCart(
  CustomerShoppingState shopping,
  List<PurchasedLine> purchased,
) async {
  for (final line in purchased) {
    if (!line.isValid) continue;
    final match = shopping.cartItems.where((c) {
      return line.matchesVariant(
        c.productId,
        c.selectedColor?.name,
        c.selectedSize?.name,
      );
    }).toList();
    if (match.isEmpty) continue;
    final item = match.first;
    if (item.quantity <= line.quantity) {
      await shopping.removeFromCart(item.id);
    } else {
      await shopping.updateQuantity(item.id, item.quantity - line.quantity);
    }
  }
}
