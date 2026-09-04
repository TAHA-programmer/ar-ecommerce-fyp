import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/admin/orders_payments/viewmodels/admin_orders_viewmodel.dart';

OrderModel _buildOrder({
  required String id,
  required String customerName,
  required DateTime orderDate,
  OrderStatus orderStatus = OrderStatus.pending,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  double total = 1000,
}) {
  return OrderModel(
    id: id,
    userId: 'test-uid',
    paymentId: 'pay_$id',
    items: [
      OrderItemModel(
        productId: 'p1',
        productName: 'Test Product',
        imagePath: 'assets/test.png',
        quantity: 1,
        unitPrice: total,
        lineTotal: total,
      ),
    ],
    orderDate: orderDate,
    subtotal: total,
    deliveryFee: 0,
    discount: 0,
    total: total,
    paymentMethod: PaymentMethod.stripeCard,
    paymentStatus: paymentStatus,
    orderStatus: orderStatus,
    deliveryAddress: AddressModel(
      fullName: customerName,
      phoneNumber: '9999999999',
      addressLine1: '123 Test Street',
      city: 'Test City',
      provinceOrState: 'Test State',
      postalCode: '00000',
    ),
    estimatedDeliveryStart: orderDate.add(const Duration(days: 7)),
    estimatedDeliveryEnd: orderDate.add(const Duration(days: 14)),
  );
}

void main() {
  late MockCommerceDatabase db;
  late AdminOrdersViewModel viewModel;

  setUp(() {
    db = MockCommerceDatabase();
    viewModel = AdminOrdersViewModel(db);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('AdminOrdersViewModel - initial & empty state', () {
    test('starts empty because MockCommerceDatabase seeds no orders', () {
      expect(db.orders, isEmpty);
      expect(viewModel.filteredOrders, isEmpty);
      expect(viewModel.totalOrdersCount, 0);
      expect(viewModel.searchQuery, '');
      expect(viewModel.statusFilter, isNull);
      expect(viewModel.paymentStatusFilter, isNull);
      expect(viewModel.hasActiveFilters, isFalse);
    });
  });

  group('AdminOrdersViewModel - search', () {
    setUp(() {
      db.addOrder(
        _buildOrder(
          id: '#TW00000001',
          customerName: 'Alice Walker',
          orderDate: DateTime(2026, 1, 1),
        ),
      );
      db.addOrder(
        _buildOrder(
          id: '#TW00000002',
          customerName: 'Bob Stone',
          orderDate: DateTime(2026, 1, 2),
        ),
      );
    });

    test('search matches by order ID, case-insensitively and trimmed', () {
      viewModel.setSearchQuery('  tw00000001  ');
      final results = viewModel.filteredOrders;
      expect(results, hasLength(1));
      expect(results.first.id, '#TW00000001');
    });

    test('search matches by customer (delivery recipient) name', () {
      viewModel.setSearchQuery('bob');
      final results = viewModel.filteredOrders;
      expect(results, hasLength(1));
      expect(results.first.deliveryAddress.fullName, 'Bob Stone');
    });

    test('search never matches on email since OrderModel has none', () {
      viewModel.setSearchQuery('bob@example.com');
      expect(viewModel.filteredOrders, isEmpty);
    });
  });

  group('AdminOrdersViewModel - order status filter', () {
    setUp(() {
      for (final status in OrderStatus.values) {
        db.addOrder(
          _buildOrder(
            id: '#TW-${status.name}',
            customerName: 'Customer ${status.name}',
            orderDate: DateTime(2026, 1, 1),
            orderStatus: status,
          ),
        );
      }
    });

    for (final status in OrderStatus.values) {
      test('filters to exactly ${status.name} orders', () {
        viewModel.setStatusFilter(status);
        final results = viewModel.filteredOrders;
        expect(results, hasLength(1));
        expect(results.first.orderStatus, status);
      });
    }

    test('null resets the order status filter back to All', () {
      viewModel.setStatusFilter(OrderStatus.shipped);
      viewModel.setStatusFilter(null);
      expect(viewModel.filteredOrders, hasLength(OrderStatus.values.length));
    });
  });

  group('AdminOrdersViewModel - payment status filter', () {
    setUp(() {
      for (final status in PaymentStatus.values) {
        db.addOrder(
          _buildOrder(
            id: '#TW-${status.name}',
            customerName: 'Customer ${status.name}',
            orderDate: DateTime(2026, 1, 1),
            paymentStatus: status,
          ),
        );
      }
    });

    for (final status in PaymentStatus.values) {
      test('filters to exactly ${status.name} payments', () {
        viewModel.setPaymentStatusFilter(status);
        final results = viewModel.filteredOrders;
        expect(results, hasLength(1));
        expect(results.first.paymentStatus, status);
      });
    }
  });

  group('AdminOrdersViewModel - combined filters', () {
    test('search + order status + payment status narrow together', () {
      db.addOrder(
        _buildOrder(
          id: '#TW00000001',
          customerName: 'Alice Walker',
          orderDate: DateTime(2026, 1, 1),
          orderStatus: OrderStatus.shipped,
          paymentStatus: PaymentStatus.paid,
        ),
      );
      db.addOrder(
        _buildOrder(
          id: '#TW00000002',
          customerName: 'Alice Walker',
          orderDate: DateTime(2026, 1, 2),
          orderStatus: OrderStatus.pending,
          paymentStatus: PaymentStatus.paid,
        ),
      );
      db.addOrder(
        _buildOrder(
          id: '#TW00000003',
          customerName: 'Someone Else',
          orderDate: DateTime(2026, 1, 3),
          orderStatus: OrderStatus.shipped,
          paymentStatus: PaymentStatus.failed,
        ),
      );

      viewModel.setSearchQuery('alice');
      viewModel.setStatusFilter(OrderStatus.shipped);
      viewModel.setPaymentStatusFilter(PaymentStatus.paid);

      final results = viewModel.filteredOrders;
      expect(results, hasLength(1));
      expect(results.first.id, '#TW00000001');
    });
  });

  group('AdminOrdersViewModel - ordering & reactivity', () {
    test('orders are always newest-first regardless of insertion order', () {
      db.addOrder(
        _buildOrder(
          id: '#TW-old',
          customerName: 'Old Order',
          orderDate: DateTime(2026, 1, 1),
        ),
      );
      db.addOrder(
        _buildOrder(
          id: '#TW-new',
          customerName: 'New Order',
          orderDate: DateTime(2026, 1, 10),
        ),
      );
      db.addOrder(
        _buildOrder(
          id: '#TW-mid',
          customerName: 'Mid Order',
          orderDate: DateTime(2026, 1, 5),
        ),
      );

      final results = viewModel.filteredOrders;
      expect(results.map((o) => o.id).toList(), [
        '#TW-new',
        '#TW-mid',
        '#TW-old',
      ]);
    });

    test('a new order added to the shared MockCommerceDatabase (e.g. by '
        'Customer checkout) appears immediately without manual sync', () {
      expect(viewModel.filteredOrders, isEmpty);

      db.addOrder(
        _buildOrder(
          id: '#TW-checkout',
          customerName: 'Checkout Customer',
          orderDate: DateTime(2026, 1, 1),
        ),
      );

      expect(viewModel.filteredOrders, hasLength(1));
      expect(viewModel.totalOrdersCount, 1);
    });
  });
}
