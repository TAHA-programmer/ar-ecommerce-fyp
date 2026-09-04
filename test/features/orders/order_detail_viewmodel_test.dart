import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/app/viewmodels/customer_order_state.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/orders/viewmodels/order_detail_viewmodel.dart';

void main() {
  group('OrderDetailViewModel Tests', () {
    late MockCommerceDatabase db;
    late CustomerOrderState orderState;
    late OrderModel mockOrder;

    setUp(() {
      db = MockCommerceDatabase();
      orderState = CustomerOrderState(db);
      mockOrder = OrderModel(
        id: 'TW123',
        userId: 'test-uid',
        paymentId: 'pay_TW123',
        items: [],
        orderDate: DateTime(2024),
        subtotal: 100,
        deliveryFee: 10,
        discount: 5,
        total: 105,
        paymentMethod: PaymentMethod.stripeCard,
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.confirmed,
        deliveryAddress: AddressModel(
          id: 'A1',
          fullName: 'John Doe',
          phoneNumber: '1234567890',
          addressLine1: '123 Street',
          city: 'City',
          provinceOrState: 'State',
          postalCode: '12345',
        ),
        estimatedDeliveryStart: DateTime(2024),
        estimatedDeliveryEnd: DateTime(2024),
      );
      db.addOrder(mockOrder);
    });

    test('Loads existing order successfully', () {
      final viewModel = OrderDetailViewModel(
        orderState: orderState,
        orderId: 'TW123',
      );

      expect(viewModel.isNotFound, isFalse);
      expect(viewModel.order, isNotNull);
      expect(viewModel.order!.id, 'TW123');
    });

    test('Sets isNotFound when order does not exist', () {
      final viewModel = OrderDetailViewModel(
        orderState: orderState,
        orderId: 'INVALID_ID',
      );

      expect(viewModel.isNotFound, isTrue);
      expect(viewModel.order, isNull);
    });

    test(
      'Live-updates when the order status changes elsewhere (e.g. Admin)',
      () {
        final viewModel = OrderDetailViewModel(
          orderState: orderState,
          orderId: 'TW123',
        );

        expect(viewModel.order!.orderStatus, OrderStatus.confirmed);

        db.updateOrderStatus('TW123', OrderStatus.shipped);

        expect(viewModel.order!.orderStatus, OrderStatus.shipped);
      },
    );
  });
}
