import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/app/viewmodels/customer_order_state.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/orders/viewmodels/my_orders_viewmodel.dart';
import 'package:twin_ar/features/address/models/address_model.dart';

void main() {
  group('MyOrdersViewModel Tests', () {
    late MockCommerceDatabase db;
    late CustomerOrderState orderState;
    late MyOrdersViewModel viewModel;

    final baseOrder = OrderModel(
      id: '123',
      userId: 'test-uid',
      paymentId: 'pay_123',
      items: [],
      orderDate: DateTime(2025, 5, 16),
      subtotal: 100,
      deliveryFee: 10,
      discount: 0,
      total: 110,
      paymentMethod: PaymentMethod.stripeCard,
      paymentStatus: PaymentStatus.paid,
      orderStatus: OrderStatus.pending,
      deliveryAddress: AddressModel(
        fullName: 'Test',
        phoneNumber: '1234567890',
        addressLine1: 'Line 1',
        city: 'City',
        provinceOrState: 'State',
        postalCode: '12345',
      ),
      estimatedDeliveryStart: DateTime.now(),
      estimatedDeliveryEnd: DateTime.now(),
    );

    setUp(() {
      db = MockCommerceDatabase();
      orderState = CustomerOrderState(db);
      viewModel = MyOrdersViewModel(orderState: orderState);
    });

    test('Initial filter is null (All)', () {
      expect(viewModel.selectedFilter, isNull);
    });

    test('Setting filter updates state and filtered orders', () {
      final order1 = OrderModel(
        id: '1',
        userId: 'test-uid',
        paymentId: 'pay_1',
        items: [],
        orderDate: DateTime(2025, 5, 16),
        subtotal: 100,
        deliveryFee: 10,
        discount: 0,
        total: 110,
        paymentMethod: PaymentMethod.stripeCard,
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.pending,
        deliveryAddress: baseOrder.deliveryAddress,
        estimatedDeliveryStart: DateTime.now(),
        estimatedDeliveryEnd: DateTime.now(),
      );

      final order2 = OrderModel(
        id: '2',
        userId: 'test-uid',
        paymentId: 'pay_2',
        items: [],
        orderDate: DateTime(2025, 5, 17),
        subtotal: 100,
        deliveryFee: 10,
        discount: 0,
        total: 110,
        paymentMethod: PaymentMethod.stripeCard,
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.confirmed,
        deliveryAddress: baseOrder.deliveryAddress,
        estimatedDeliveryStart: DateTime.now(),
        estimatedDeliveryEnd: DateTime.now(),
      );

      db.addOrder(order1);
      db.addOrder(order2);

      expect(viewModel.filteredOrders.length, 2);

      viewModel.setFilter(OrderStatus.confirmed);
      expect(viewModel.selectedFilter, OrderStatus.confirmed);
      expect(viewModel.filteredOrders.length, 1);
      expect(viewModel.filteredOrders.first.id, '2');

      viewModel.setFilter(null);
      expect(viewModel.selectedFilter, isNull);
      expect(viewModel.filteredOrders.length, 2);
    });

    test('Orders are sorted newest first', () {
      final order1 = OrderModel(
        id: '1',
        userId: 'test-uid',
        paymentId: 'pay_1',
        items: [],
        orderDate: DateTime(2025, 5, 16),
        subtotal: 100,
        deliveryFee: 10,
        discount: 0,
        total: 110,
        paymentMethod: PaymentMethod.stripeCard,
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.pending,
        deliveryAddress: baseOrder.deliveryAddress,
        estimatedDeliveryStart: DateTime.now(),
        estimatedDeliveryEnd: DateTime.now(),
      );

      final order2 = OrderModel(
        id: '2',
        userId: 'test-uid',
        paymentId: 'pay_2',
        items: [],
        orderDate: DateTime(2025, 5, 17),
        subtotal: 100,
        deliveryFee: 10,
        discount: 0,
        total: 110,
        paymentMethod: PaymentMethod.stripeCard,
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.pending,
        deliveryAddress: baseOrder.deliveryAddress,
        estimatedDeliveryStart: DateTime.now(),
        estimatedDeliveryEnd: DateTime.now(),
      );

      // order1 added first, order2 added second
      db.addOrder(order1);
      db.addOrder(order2);

      // Verify the sorted order places the newer date first
      expect(viewModel.filteredOrders.first.id, '2'); // May 17
      expect(viewModel.filteredOrders.last.id, '1'); // May 16
    });
  });
}
