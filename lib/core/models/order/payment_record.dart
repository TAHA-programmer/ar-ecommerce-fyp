import 'order_model.dart';

class PaymentRecord {
  final String paymentId;

  /// Owner uid (Phase 8.9), denormalized from the linked order - Firestore
  /// rules/queries need a directly-filterable/checkable field on this
  /// document itself, not a cross-collection join.
  final String userId;

  /// The order this payment belongs to. Required as of Phase 8.9 - every
  /// payment is now always created atomically together with its order (see
  /// `firestore.rules`' `paymentMatchesOrder`), so an "unlinked payment"
  /// concept no longer exists.
  final String orderId;

  final double amount;
  final PaymentMethod method;
  final PaymentStatus status;
  final DateTime createdAt;

  PaymentRecord({
    required this.paymentId,
    required this.userId,
    required this.orderId,
    required this.amount,
    required this.method,
    required this.status,
    required this.createdAt,
  });
}
