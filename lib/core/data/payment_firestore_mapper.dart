import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/order/order_model.dart';
import '../models/order/payment_record.dart';

// Firestore <-> PaymentRecord mapping for `payments/{paymentId}` (Phase
// 8.9). Same defensive-typed-read convention as
// `order_firestore_mapper.dart` (see its header comment) - a payment
// document can also be created by a real, non-admin customer client.

String _str(dynamic v, [String fallback = '']) => v is String ? v : fallback;

double _numOr(dynamic v, [double fallback = 0]) =>
    v is num ? v.toDouble() : fallback;

DateTime _dateFromTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return DateTime.now();
}

PaymentMethod _paymentMethodFromName(dynamic v) {
  for (final m in PaymentMethod.values) {
    if (m.name == v) return m;
  }
  return PaymentMethod.stripeCard;
}

PaymentStatus _paymentStatusFromName(dynamic v) {
  for (final s in PaymentStatus.values) {
    if (s.name == v) return s;
  }
  return PaymentStatus.pending;
}

/// Read direction: a Firestore `payments/{id}` document -> [PaymentRecord].
PaymentRecord paymentRecordFromFirestore(String id, Map<String, dynamic> data) {
  return PaymentRecord(
    paymentId: id,
    userId: _str(data['userId']),
    orderId: _str(data['orderId']),
    amount: _numOr(data['amount']),
    method: _paymentMethodFromName(data['method']),
    status: _paymentStatusFromName(data['status']),
    createdAt: _dateFromTimestamp(data['createdAt']),
  );
}

extension PaymentRecordFirestoreMapper on PaymentRecord {
  /// Create-only write map.
  ///
  /// Phase 8.13.6: no production code calls this - payments are created only
  /// by the Cloud Functions (see `order_firestore_mapper.dart`'s
  /// `toFirestoreCreateMap()` note), and `firestore.rules` `payments`
  /// `create`/`update`/`delete` are all `if false`. Kept as the documented
  /// counterpart to [paymentRecordFromFirestore] and covered by
  /// `test/core/data/payment_firestore_mapper_test.dart`.
  Map<String, dynamic> toFirestoreCreateMap() {
    return {
      'userId': userId,
      'orderId': orderId,
      'amount': amount,
      'method': method.name,
      'status': status.name,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }
}
