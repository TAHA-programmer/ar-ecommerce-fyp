/// The notification types the server writes into a customer's inbox
/// (`functions/src/lib/notifications/types.ts`, `CUSTOMER_NOTIFICATION_TYPES`).
/// Admin types never appear in an inbox (plan §4.2) but ARE valid in a push
/// payload, so they are parsed separately by [NotificationPayloadType].
enum NotificationType {
  orderPlaced('order_placed'),
  orderConfirmed('order_confirmed'),
  orderShipped('order_shipped'),
  orderDelivered('order_delivered'),
  orderCancelled('order_cancelled'),
  paymentRefunded('payment_refunded'),
  reviewHidden('review_hidden'),
  reviewRejected('review_rejected'),
  reviewRestored('review_restored'),

  /// An unrecognised wire value (a newer server type on an older app). It is
  /// still shown (generic icon) but never routes anywhere.
  unknown('unknown');

  const NotificationType(this.wire);

  final String wire;

  static NotificationType fromWire(String? value) {
    for (final t in NotificationType.values) {
      if (t != NotificationType.unknown && t.wire == value) return t;
    }
    return NotificationType.unknown;
  }

  bool get isOrder =>
      this == orderPlaced ||
      this == orderConfirmed ||
      this == orderShipped ||
      this == orderDelivered ||
      this == orderCancelled;

  bool get isReview =>
      this == reviewHidden || this == reviewRejected || this == reviewRestored;
}

/// Every `type` value an FCM data payload may carry (customer + admin). The
/// app maps each to a HARD-CODED destination (plan §4.6) - the payload never
/// supplies a route name or URL.
enum NotificationPayloadType {
  orderPlaced('order_placed'),
  orderConfirmed('order_confirmed'),
  orderShipped('order_shipped'),
  orderDelivered('order_delivered'),
  orderCancelled('order_cancelled'),
  paymentRefunded('payment_refunded'),
  reviewHidden('review_hidden'),
  reviewRejected('review_rejected'),
  reviewRestored('review_restored'),
  adminNewOrder('admin_new_order'),
  adminLowStock('admin_low_stock'),
  adminOutOfStock('admin_out_of_stock'),
  adminReviewFlagged('admin_review_flagged'),
  adminPaymentIssue('admin_payment_issue');

  const NotificationPayloadType(this.wire);

  final String wire;

  /// `null` for an unknown type: the payload is then ignored entirely.
  static NotificationPayloadType? tryParse(String? value) {
    for (final t in NotificationPayloadType.values) {
      if (t.wire == value) return t;
    }
    return null;
  }

  bool get isAdmin => wire.startsWith('admin_');
}
