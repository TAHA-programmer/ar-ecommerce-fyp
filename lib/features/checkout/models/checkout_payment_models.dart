/// Plain data models for the Phase 8.13.5 Stripe checkout flow.
///
/// All values that matter for money or order identity come from the SERVER
/// (`createPaymentIntent`'s response and the `checkoutSessions/{id}`
/// document). The client never computes or trusts its own totals here.
library;

/// Server-authoritative order totals, in whole rupees.
class CheckoutTotals {
  final int subtotal;
  final int deliveryFee;
  final int discount;
  final int total;

  const CheckoutTotals({
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
  });

  static int _asInt(Object? v) => v is num ? v.round() : 0;

  factory CheckoutTotals.fromMap(Map<String, dynamic> map) => CheckoutTotals(
    subtotal: _asInt(map['subtotal']),
    deliveryFee: _asInt(map['deliveryFee']),
    discount: _asInt(map['discount']),
    total: _asInt(map['total']),
  );
}

/// One cart line as sent to `createPaymentIntent` - references only, never
/// prices or stock (the server resolves those).
class CheckoutLineItemRequest {
  final String productId;
  final int quantity;
  final String? selectedColor;
  final String? selectedSize;

  const CheckoutLineItemRequest({
    required this.productId,
    required this.quantity,
    this.selectedColor,
    this.selectedSize,
  });

  Map<String, dynamic> toMap() => {
    'productId': productId,
    'quantity': quantity,
    if (selectedColor != null) 'selectedColor': selectedColor,
    if (selectedSize != null) 'selectedSize': selectedSize,
  };
}

/// The subset of `createPaymentIntent`'s response the client needs for
/// PaymentSheet + session tracking.
class CreatePaymentIntentResult {
  final String checkoutSessionId;
  final String paymentIntentClientSecret;

  /// Stripe charge amount in the currency's smallest unit (paisa for PKR).
  final int amountMinor;
  final String currency;
  final DateTime expiresAt;
  final CheckoutTotals totals;

  const CreatePaymentIntentResult({
    required this.checkoutSessionId,
    required this.paymentIntentClientSecret,
    required this.amountMinor,
    required this.currency,
    required this.expiresAt,
    required this.totals,
  });

  factory CreatePaymentIntentResult.fromMap(Map<String, dynamic> map) {
    final expiresRaw = map['expiresAt'];
    final expiresMs = expiresRaw is num ? expiresRaw.toInt() : 0;
    return CreatePaymentIntentResult(
      checkoutSessionId: (map['checkoutSessionId'] ?? '').toString(),
      paymentIntentClientSecret: (map['paymentIntentClientSecret'] ?? '')
          .toString(),
      amountMinor: map['amount'] is num ? (map['amount'] as num).toInt() : 0,
      currency: (map['currency'] ?? 'pkr').toString(),
      expiresAt: DateTime.fromMillisecondsSinceEpoch(
        expiresMs > 0 ? expiresMs : DateTime.now().millisecondsSinceEpoch,
      ),
      totals: CheckoutTotals.fromMap(
        (map['totals'] as Map?)?.cast<String, dynamic>() ?? const {},
      ),
    );
  }
}

/// The authoritative lifecycle status of a server-owned checkout session.
enum CheckoutSessionStatus { reserved, succeeded, failed, expired, unknown }

CheckoutSessionStatus checkoutSessionStatusFrom(Object? raw) {
  switch (raw) {
    case 'reserved':
      return CheckoutSessionStatus.reserved;
    case 'succeeded':
      return CheckoutSessionStatus.succeeded;
    case 'failed':
      return CheckoutSessionStatus.failed;
    case 'expired':
      return CheckoutSessionStatus.expired;
    default:
      return CheckoutSessionStatus.unknown;
  }
}

/// A live snapshot of `checkoutSessions/{id}` - the client only ever READS this.
class CheckoutSessionUpdate {
  final CheckoutSessionStatus status;
  final String? orderId;
  final CheckoutTotals? totals;

  const CheckoutSessionUpdate({
    required this.status,
    this.orderId,
    this.totals,
  });

  bool get isSucceededWithOrder =>
      status == CheckoutSessionStatus.succeeded &&
      orderId != null &&
      orderId!.isNotEmpty;

  bool get isTerminalFailure =>
      status == CheckoutSessionStatus.failed ||
      status == CheckoutSessionStatus.expired;
}

/// One line that a completed checkout actually purchased - the
/// `(productId, colour, size)` tuple plus the quantity bought. Used by the
/// Phase 8.13.6 late-success cart reconciliation to remove exactly what was
/// paid for and nothing that was added to the cart afterwards. Colour/size
/// are the enum *names* (the same strings `checkoutSessions/{id}.items[]`
/// stores), never resolved objects.
class PurchasedLine {
  final String productId;
  final String? selectedColor;
  final String? selectedSize;
  final int quantity;

  const PurchasedLine({
    required this.productId,
    required this.quantity,
    this.selectedColor,
    this.selectedSize,
  });

  factory PurchasedLine.fromSessionItem(Map<String, dynamic> item) {
    final rawQty = item['quantity'];
    final color = item['selectedColor'];
    final size = item['selectedSize'];
    return PurchasedLine(
      productId: (item['productId'] ?? '').toString(),
      quantity: rawQty is num && rawQty > 0 ? rawQty.toInt() : 0,
      selectedColor: color is String && color.isNotEmpty ? color : null,
      selectedSize: size is String && size.isNotEmpty ? size : null,
    );
  }

  bool get isValid => productId.isNotEmpty && quantity > 0;

  /// Does this purchased line refer to the same product/variant as [other]
  /// (ignoring quantity)? `other` values are enum names too.
  bool matchesVariant(
    String otherProductId,
    String? otherColor,
    String? otherSize,
  ) =>
      productId == otherProductId &&
      selectedColor == otherColor &&
      selectedSize == otherSize;
}
