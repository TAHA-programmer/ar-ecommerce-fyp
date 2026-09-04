import '../models/checkout_payment_models.dart';

/// The reason a checkout payment step could not complete. The ViewModel maps
/// each kind to a natural, existing-style customer message; the raw
/// callable/Stripe error text is never shown.
enum CheckoutErrorKind {
  /// `STRIPE_PUBLISHABLE_KEY` was not provided at build time.
  notConfigured,

  /// The user dismissed Stripe PaymentSheet without paying. Cart kept; the
  /// same attempt can simply be retried (the reservation still stands).
  paymentSheetCancelled,

  /// Card declined / authentication failed in PaymentSheet.
  cardDeclined,

  /// The server refused the checkout: a product is gone / draft / inactive,
  /// or a chosen variant is unavailable.
  productUnavailable,

  /// The server refused the checkout: not enough stock.
  insufficientStock,

  /// The selected delivery address could not be found / is incomplete.
  addressProblem,

  /// A prior attempt with this idempotency key already completed or is closed.
  checkoutClosed,

  /// The reservation window expired before payment completed.
  reservationExpired,

  /// Network / timeout reaching the server or Stripe. Safe to retry.
  network,

  /// Anything else - a generic, safe fallback.
  unknown,
}

/// Thrown by [CheckoutPaymentService] for every non-success outcome. Carries
/// a machine [kind] and an already-customer-safe [message].
class CheckoutPaymentException implements Exception {
  final CheckoutErrorKind kind;
  final String message;

  const CheckoutPaymentException(this.kind, this.message);

  /// `true` when starting a fresh checkout attempt (a NEW idempotency key) is
  /// the right recovery. `false` means the SAME attempt can be retried
  /// (e.g. cancel / decline - the reservation still stands).
  bool get requiresFreshAttempt =>
      kind == CheckoutErrorKind.checkoutClosed ||
      kind == CheckoutErrorKind.reservationExpired ||
      kind == CheckoutErrorKind.insufficientStock ||
      kind == CheckoutErrorKind.productUnavailable ||
      kind == CheckoutErrorKind.addressProblem;

  @override
  String toString() => 'CheckoutPaymentException($kind): $message';
}

/// The seam between [CheckoutViewModel] and the outside world
/// (Cloud Functions + Stripe PaymentSheet + the `checkoutSessions` listener).
/// Every method is mockable so the ViewModel is testable with no real Stripe
/// or Firebase.
abstract class CheckoutPaymentService {
  /// `false` when the publishable key is missing - the ViewModel then shows a
  /// "card payment unavailable" state and never calls the methods below.
  bool get isConfigured;

  /// Calls the `createPaymentIntent` callable in `us-central1`. Throws
  /// [CheckoutPaymentException] on any failure.
  Future<CreatePaymentIntentResult> createPaymentIntent({
    required List<CheckoutLineItemRequest> items,
    required String addressId,
    required String idempotencyKey,
  });

  /// Initializes and presents Stripe PaymentSheet for [clientSecret].
  ///
  /// Returns normally once the sheet closes with the payment submitted
  /// (which is NOT the same as the order succeeding). Throws
  /// [CheckoutPaymentException] with kind [CheckoutErrorKind.paymentSheetCancelled]
  /// on user dismissal, or [CheckoutErrorKind.cardDeclined] on a decline.
  Future<void> presentPaymentSheet({required String clientSecret});

  /// A live stream of the server-owned `checkoutSessions/{sessionId}` document.
  /// The client only ever reads this.
  Stream<CheckoutSessionUpdate> watchSession(String sessionId);

  /// Phase 8.13.6 - late-success recovery. Reads (read-only) the customer's
  /// own recently-`succeeded` `checkoutSessions` and returns the lines those
  /// checkouts purchased, so [CheckoutCartReconciler] can clear exactly those
  /// items from the cart when the checkout screen was closed before the
  /// (possibly delayed) webhook / scheduler finalized the order. Returns an
  /// empty list on any read failure - reconciliation is best-effort.
  Future<List<PurchasedLine>> recentlyPurchasedLines(String uid);
}
