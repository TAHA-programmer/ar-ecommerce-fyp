import '../../../features/address/models/address_model.dart';
import 'order_item_model.dart';

enum PaymentMethod { stripeCard }

extension PaymentMethodX on PaymentMethod {
  String get displayName {
    switch (this) {
      case PaymentMethod.stripeCard:
        return 'Stripe';
    }
  }
}

enum PaymentStatus { pending, paid, failed }

extension PaymentStatusX on PaymentStatus {
  String get displayName {
    switch (this) {
      case PaymentStatus.pending:
        return 'Pending';
      case PaymentStatus.paid:
        return 'Paid';
      case PaymentStatus.failed:
        return 'Failed';
    }
  }
}

enum OrderStatus { pending, confirmed, shipped, delivered, cancelled }

extension OrderStatusX on OrderStatus {
  String get displayName {
    switch (this) {
      case OrderStatus.pending:
        return 'Pending';
      case OrderStatus.confirmed:
        return 'Confirmed';
      case OrderStatus.shipped:
        return 'Shipped';
      case OrderStatus.delivered:
        return 'Delivered';
      case OrderStatus.cancelled:
        return 'Cancelled';
    }
  }
}

class OrderModel {
  final String id;

  /// Owner uid (Phase 8.9). Deliberately NOT a [copyWith] parameter - the
  /// only way to get an [OrderModel] with a different [userId] is to
  /// construct a brand-new one, so no call site (including a future one)
  /// can ever accidentally reassign an order's ownership via copyWith.
  final String userId;

  /// The exact payment document this order was atomically created with
  /// (Phase 8.9 - see `firestore.rules`' `orderMatchesPayment`/
  /// `paymentMatchesOrder`). Also excluded from [copyWith] for the same
  /// immutability-by-construction reason as [userId].
  final String paymentId;

  final List<OrderItemModel> items;
  final DateTime orderDate;

  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double total;

  final PaymentMethod paymentMethod;
  final PaymentStatus paymentStatus;
  final OrderStatus orderStatus;

  final AddressModel deliveryAddress;

  final DateTime estimatedDeliveryStart;
  final DateTime estimatedDeliveryEnd;

  OrderModel({
    required this.id,
    required this.userId,
    required this.paymentId,
    required this.items,
    required this.orderDate,
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
    required this.paymentMethod,
    required this.paymentStatus,
    required this.orderStatus,
    required this.deliveryAddress,
    required this.estimatedDeliveryStart,
    required this.estimatedDeliveryEnd,
  });

  /// [userId]/[paymentId] are never parameters here - see their doc
  /// comments. Every other field may be replaced, matching the pre-8.9
  /// contract (used by [MockCommerceDatabase.updateOrderStatus] /
  /// `FirestoreCommerceDatabase`'s Admin status-update path).
  OrderModel copyWith({
    String? id,
    List<OrderItemModel>? items,
    DateTime? orderDate,
    double? subtotal,
    double? deliveryFee,
    double? discount,
    double? total,
    PaymentMethod? paymentMethod,
    PaymentStatus? paymentStatus,
    OrderStatus? orderStatus,
    AddressModel? deliveryAddress,
    DateTime? estimatedDeliveryStart,
    DateTime? estimatedDeliveryEnd,
  }) {
    return OrderModel(
      id: id ?? this.id,
      userId: userId,
      paymentId: paymentId,
      items: items ?? this.items,
      orderDate: orderDate ?? this.orderDate,
      subtotal: subtotal ?? this.subtotal,
      deliveryFee: deliveryFee ?? this.deliveryFee,
      discount: discount ?? this.discount,
      total: total ?? this.total,
      paymentMethod: paymentMethod ?? this.paymentMethod,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      orderStatus: orderStatus ?? this.orderStatus,
      deliveryAddress: deliveryAddress ?? this.deliveryAddress,
      estimatedDeliveryStart:
          estimatedDeliveryStart ?? this.estimatedDeliveryStart,
      estimatedDeliveryEnd: estimatedDeliveryEnd ?? this.estimatedDeliveryEnd,
    );
  }
}
