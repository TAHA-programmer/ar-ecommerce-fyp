import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/address/models/address_model.dart';
import '../models/order/order_item_model.dart';
import '../models/order/order_model.dart';
import '../models/product/product_image_ref.dart';

// Firestore <-> OrderModel mapping for `orders/{orderId}` (Phase 8.9).
//
// Unlike `product_firestore_mapper.dart`/`category_firestore_mapper.dart`
// (both admin-only writes), an order document can be created by a real,
// non-admin customer client - `firestore.rules`' `isValidOrderCreate`
// enforces the actual security boundary at write time, but the READ side
// here still must never crash on a slightly malformed/legacy document, so
// every field uses an explicit `is T` type check (never an unsafe `as T?`
// cast, which throws for a present-but-wrong-typed field - see
// `09_BACKEND_INTEGRATION_PLAN.md`'s Phase 8.8 Pre-Deployment Correction
// Pass for the exact bug class this avoids).

String _str(dynamic v, [String fallback = '']) => v is String ? v : fallback;

double _numOr(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

int _intOr(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

bool _boolOr(dynamic v, [bool fallback = false]) => v is bool ? v : fallback;

String? _strOrNull(dynamic v) => v is String ? v : null;

/// A `serverTimestamp()` write can locally echo as null before the server
/// resolves it (e.g. a snapshot event arriving before ack) - falls back to
/// "now" as a display-only approximation; the next snapshot carries the
/// real resolved value. Never throws on a missing/pending/malformed field.
DateTime _dateFromTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return DateTime.now();
}

PaymentMethod _paymentMethodFromName(dynamic v) {
  // Only one real value exists today - never a malformed-data concern, but
  // written explicitly rather than assumed, matching every other enum
  // parser in this file.
  for (final m in PaymentMethod.values) {
    if (m.name == v) return m;
  }
  return PaymentMethod.stripeCard;
}

PaymentStatus _paymentStatusFromName(dynamic v) {
  for (final s in PaymentStatus.values) {
    if (s.name == v) return s;
  }
  // Unknown/missing must never silently resolve to 'paid' - default to the
  // least-permissive-looking real value instead.
  return PaymentStatus.pending;
}

OrderStatus _orderStatusFromName(dynamic v) {
  for (final s in OrderStatus.values) {
    if (s.name == v) return s;
  }
  return OrderStatus.pending;
}

ProductImageSource _imageSourceFromName(dynamic v) {
  for (final s in ProductImageSource.values) {
    if (s.name == v) return s;
  }
  return ProductImageSource.network;
}

List<OrderItemModel> _itemsFromData(dynamic raw) {
  if (raw is! List) return const [];
  final result = <OrderItemModel>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final map = Map<String, dynamic>.from(entry);
    result.add(
      OrderItemModel(
        productId: _str(map['productId']),
        productName: _str(map['productName']),
        imagePath: _str(map['imagePath']),
        imageSource: _imageSourceFromName(map['imageSource']),
        quantity: _intOr(map['quantity'], 1),
        selectedSize: _strOrNull(map['selectedSize']),
        selectedColor: _strOrNull(map['selectedColor']),
        unitPrice: _numOr(map['unitPrice']),
        lineTotal: _numOr(map['lineTotal']),
      ),
    );
  }
  return result;
}

Map<String, dynamic> _itemToMap(OrderItemModel item) => {
  'productId': item.productId,
  'productName': item.productName,
  'imagePath': item.imagePath,
  'imageSource': item.imageSource.name,
  'quantity': item.quantity,
  'selectedSize': item.selectedSize,
  'selectedColor': item.selectedColor,
  'unitPrice': item.unitPrice,
  'lineTotal': item.lineTotal,
};

AddressModel _addressFromData(dynamic raw) {
  if (raw is! Map) {
    return AddressModel(
      fullName: '',
      phoneNumber: '',
      addressLine1: '',
      city: '',
      provinceOrState: '',
      postalCode: '',
    );
  }
  final map = Map<String, dynamic>.from(raw);
  return AddressModel(
    id: _strOrNull(map['id']),
    label: _strOrNull(map['label']),
    fullName: _str(map['fullName']),
    phoneNumber: _str(map['phoneNumber']),
    addressLine1: _str(map['addressLine1']),
    addressLine2: _strOrNull(map['addressLine2']),
    city: _str(map['city']),
    provinceOrState: _str(map['provinceOrState']),
    postalCode: _str(map['postalCode']),
    isDefault: _boolOr(map['isDefault']),
  );
}

/// Every key is always written, including nullable ones (as explicit
/// `null`), so `firestore.rules`' `isValidDeliveryAddress` can validate an
/// exact `hasAll`/`hasOnly` field set on this nested map.
Map<String, dynamic> _addressToMap(AddressModel address) => {
  'id': address.id,
  'label': address.label,
  'fullName': address.fullName,
  'phoneNumber': address.phoneNumber,
  'addressLine1': address.addressLine1,
  'addressLine2': address.addressLine2,
  'city': address.city,
  'provinceOrState': address.provinceOrState,
  'postalCode': address.postalCode,
  'isDefault': address.isDefault,
};

/// Read direction: a Firestore `orders/{id}` document -> [OrderModel].
OrderModel orderModelFromFirestore(String id, Map<String, dynamic> data) {
  return OrderModel(
    id: id,
    userId: _str(data['userId']),
    paymentId: _str(data['paymentId']),
    items: _itemsFromData(data['items']),
    orderDate: _dateFromTimestamp(data['orderDate']),
    subtotal: _numOr(data['subtotal']),
    deliveryFee: _numOr(data['deliveryFee']),
    discount: _numOr(data['discount']),
    total: _numOr(data['total']),
    paymentMethod: _paymentMethodFromName(data['paymentMethod']),
    paymentStatus: _paymentStatusFromName(data['paymentStatus']),
    orderStatus: _orderStatusFromName(data['orderStatus']),
    deliveryAddress: _addressFromData(data['deliveryAddress']),
    estimatedDeliveryStart: _dateFromTimestamp(data['estimatedDeliveryStart']),
    estimatedDeliveryEnd: _dateFromTimestamp(data['estimatedDeliveryEnd']),
  );
}

extension OrderModelFirestoreMapper on OrderModel {
  /// Create-only write map.
  ///
  /// Phase 8.13.6: NO production code calls this any more - orders are
  /// created only by the `stripeWebhook` / `releaseExpiredReservations`
  /// Cloud Functions from the authoritative `checkoutSessions` snapshot (see
  /// `functions/src/lib/orderFromSession.ts`), and `firestore.rules`
  /// `orders` `create` is `if false` for every client. It is retained as the
  /// documented counterpart to [orderModelFromFirestore] and is exercised by
  /// `test/core/data/order_firestore_mapper_test.dart`'s round-trip check.
  ///
  /// `id` is deliberately excluded (it's the document's own key, not a field
  /// inside it, mirroring `product_firestore_mapper.dart`'s convention).
  Map<String, dynamic> toFirestoreCreateMap() {
    return {
      'userId': userId,
      'paymentId': paymentId,
      'items': items.map(_itemToMap).toList(),
      'orderDate': FieldValue.serverTimestamp(),
      'subtotal': subtotal,
      'deliveryFee': deliveryFee,
      'discount': discount,
      'total': total,
      'paymentMethod': paymentMethod.name,
      'paymentStatus': paymentStatus.name,
      'orderStatus': orderStatus.name,
      'deliveryAddress': _addressToMap(deliveryAddress),
      'estimatedDeliveryStart': Timestamp.fromDate(estimatedDeliveryStart),
      'estimatedDeliveryEnd': Timestamp.fromDate(estimatedDeliveryEnd),
    };
  }
}
