import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';

OrderModel _order({String id = '#TW1', String userId = 'alice'}) {
  return OrderModel(
    id: id,
    userId: userId,
    paymentId: 'pay_1',
    items: const [],
    orderDate: DateTime(2026, 1, 1),
    subtotal: 100,
    deliveryFee: 0,
    discount: 0,
    total: 100,
    paymentMethod: PaymentMethod.stripeCard,
    paymentStatus: PaymentStatus.paid,
    orderStatus: OrderStatus.pending,
    deliveryAddress: AddressModel(
      fullName: 'Test',
      phoneNumber: '1',
      addressLine1: 'L1',
      city: 'C',
      provinceOrState: 'S',
      postalCode: '0',
    ),
    estimatedDeliveryStart: DateTime(2026, 1, 8),
    estimatedDeliveryEnd: DateTime(2026, 1, 15),
  );
}

void main() {
  group('OrderModel.copyWith', () {
    test(
      'preserves userId and paymentId - neither is a copyWith parameter',
      () {
        final order = _order(userId: 'alice');
        final updated = order.copyWith(orderStatus: OrderStatus.confirmed);

        expect(updated.userId, 'alice');
        expect(updated.paymentId, 'pay_1');
        expect(updated.orderStatus, OrderStatus.confirmed);
      },
    );

    test('id remains a copyWith parameter (unchanged pre-8.9 behavior)', () {
      final order = _order();
      final updated = order.copyWith(id: '#TW2');
      expect(updated.id, '#TW2');
    });
  });
}
