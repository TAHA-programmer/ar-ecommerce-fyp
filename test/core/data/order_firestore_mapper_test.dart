import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/order_firestore_mapper.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';

OrderModel _order() {
  return OrderModel(
    id: '#TW1',
    userId: 'alice',
    paymentId: 'pay_1',
    items: [
      OrderItemModel(
        productId: 'p1',
        productName: 'Test Product',
        imagePath: 'assets/test.png',
        selectedSize: 'M',
        selectedColor: 'Blue',
        quantity: 2,
        unitPrice: 500,
        lineTotal: 1000,
      ),
    ],
    orderDate: DateTime(2026, 1, 1),
    subtotal: 1000,
    deliveryFee: 100,
    discount: 50,
    total: 1050,
    paymentMethod: PaymentMethod.stripeCard,
    paymentStatus: PaymentStatus.paid,
    orderStatus: OrderStatus.pending,
    deliveryAddress: AddressModel(
      id: 'a1',
      label: 'Home',
      fullName: 'Alice',
      phoneNumber: '9999999999',
      addressLine1: 'Line 1',
      addressLine2: 'Line 2',
      city: 'City',
      provinceOrState: 'State',
      postalCode: '00000',
    ),
    estimatedDeliveryStart: DateTime(2026, 1, 8),
    estimatedDeliveryEnd: DateTime(2026, 1, 15),
  );
}

void main() {
  group('order_firestore_mapper', () {
    test(
      'toFirestoreCreateMap -> orderModelFromFirestore round-trips '
      'every field except orderDate (which uses serverTimestamp on write)',
      () {
        final order = _order();
        final map = order.toFirestoreCreateMap();

        // orderDate is FieldValue.serverTimestamp() on write - simulate a
        // resolved server value for the read-side round-trip.
        final resolvedMap = {
          ...map,
          'orderDate': Timestamp.fromDate(order.orderDate),
        };

        final reloaded = orderModelFromFirestore('#TW1', resolvedMap);

        expect(reloaded.id, order.id);
        expect(reloaded.userId, order.userId);
        expect(reloaded.paymentId, order.paymentId);
        expect(reloaded.items.length, 1);
        expect(reloaded.items.first.productId, 'p1');
        expect(reloaded.items.first.selectedSize, 'M');
        expect(reloaded.items.first.selectedColor, 'Blue');
        expect(reloaded.subtotal, order.subtotal);
        expect(reloaded.deliveryFee, order.deliveryFee);
        expect(reloaded.discount, order.discount);
        expect(reloaded.total, order.total);
        expect(reloaded.paymentMethod, PaymentMethod.stripeCard);
        expect(reloaded.paymentStatus, PaymentStatus.paid);
        expect(reloaded.orderStatus, OrderStatus.pending);
        expect(reloaded.deliveryAddress.fullName, 'Alice');
        expect(reloaded.deliveryAddress.addressLine2, 'Line 2');
        expect(reloaded.estimatedDeliveryStart, order.estimatedDeliveryStart);
        expect(reloaded.estimatedDeliveryEnd, order.estimatedDeliveryEnd);
      },
    );

    test('toFirestoreCreateMap never includes "id" (it is the document key, '
        'not a field)', () {
      expect(_order().toFirestoreCreateMap().containsKey('id'), isFalse);
    });

    test('a present-but-wrong-typed field never throws - falls back to a '
        'safe default (truly defensive: uses "is String"/"is num" checks, '
        'never an unsafe "as String?" cast)', () {
      final malformed = <String, dynamic>{
        'userId': 123, // wrong type: should be String
        'paymentId': null,
        'items': 'not-a-list',
        'orderDate': null,
        'subtotal': 'not-a-number',
        'deliveryFee': null,
        'discount': null,
        'total': null,
        'paymentMethod': 42,
        'paymentStatus': 'bogus',
        'orderStatus': 'bogus',
        'deliveryAddress': 'not-a-map',
        'estimatedDeliveryStart': null,
        'estimatedDeliveryEnd': null,
      };

      expect(
        () => orderModelFromFirestore('#TW-malformed', malformed),
        returnsNormally,
      );

      final result = orderModelFromFirestore('#TW-malformed', malformed);
      expect(result.userId, ''); // safe fallback, not a thrown TypeError
      expect(result.items, isEmpty);
      expect(result.subtotal, 0);
      // Unknown/malformed status must never silently resolve to the most
      // permissive-looking real value.
      expect(result.paymentStatus, PaymentStatus.pending);
      expect(result.orderStatus, OrderStatus.pending);
    });

    test('a missing field falls back to a safe default, never throws', () {
      expect(
        () => orderModelFromFirestore('#TW-empty', <String, dynamic>{}),
        returnsNormally,
      );
    });
  });
}
