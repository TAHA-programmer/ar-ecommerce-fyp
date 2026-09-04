import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/customer_order_state.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/admin/dashboard/viewmodels/admin_dashboard_viewmodel.dart';
import 'package:twin_ar/features/admin/orders_payments/viewmodels/admin_order_detail_viewmodel.dart';
import 'package:twin_ar/features/admin/orders_payments/viewmodels/admin_orders_viewmodel.dart';
import 'package:twin_ar/features/orders/viewmodels/my_orders_viewmodel.dart';
import 'package:twin_ar/features/orders/viewmodels/order_detail_viewmodel.dart';

OrderModel _buildOrder({
  required String id,
  String customerName = 'Alice Walker',
  OrderStatus orderStatus = OrderStatus.pending,
  DateTime? orderDate,
}) {
  final date = orderDate ?? DateTime(2026, 1, 1);
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
        unitPrice: 1000,
        lineTotal: 1000,
      ),
    ],
    orderDate: date,
    subtotal: 1000,
    deliveryFee: 0,
    discount: 0,
    total: 1000,
    paymentMethod: PaymentMethod.stripeCard,
    paymentStatus: PaymentStatus.paid,
    orderStatus: orderStatus,
    deliveryAddress: AddressModel(
      fullName: customerName,
      phoneNumber: '9999999999',
      addressLine1: '123 Test Street',
      city: 'Test City',
      provinceOrState: 'Test State',
      postalCode: '00000',
    ),
    estimatedDeliveryStart: date.add(const Duration(days: 7)),
    estimatedDeliveryEnd: date.add(const Duration(days: 14)),
  );
}

void main() {
  late MockCommerceDatabase db;

  setUp(() {
    db = MockCommerceDatabase();
  });

  group('AdminOrderDetailViewModel - resolving the order', () {
    test('resolves the correct order by id', () {
      db.addOrder(_buildOrder(id: '#TW00000001'));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW00000001');
      addTearDown(vm.dispose);

      expect(vm.isNotFound, isFalse);
      expect(vm.order, isNotNull);
      expect(vm.order!.id, '#TW00000001');
    });

    test('marks isNotFound when the orderId does not exist', () {
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW-missing');
      addTearDown(vm.dispose);

      expect(vm.isNotFound, isTrue);
      expect(vm.order, isNull);
    });
  });

  group('AdminOrderDetailViewModel - linked payment lookup', () {
    test('resolves the matching PaymentRecord when one exists', () {
      db.addOrder(_buildOrder(id: '#TW00000001'));
      db.addPayment(
        PaymentRecord(
          paymentId: 'pay_00000001',
          userId: 'test-uid',
          orderId: '#TW00000001',
          amount: 1000,
          method: PaymentMethod.stripeCard,
          status: PaymentStatus.paid,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW00000001');
      addTearDown(vm.dispose);

      expect(vm.linkedPayment, isNotNull);
      expect(vm.linkedPayment!.paymentId, 'pay_00000001');
    });

    test('returns null safely when no payment is linked', () {
      db.addOrder(_buildOrder(id: '#TW00000001'));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW00000001');
      addTearDown(vm.dispose);

      expect(vm.linkedPayment, isNull);
    });
  });

  group('AdminOrderDetailViewModel - valid transitions', () {
    final validCases = <OrderStatus, List<OrderStatus>>{
      OrderStatus.pending: [OrderStatus.confirmed, OrderStatus.cancelled],
      OrderStatus.confirmed: [OrderStatus.shipped, OrderStatus.cancelled],
      OrderStatus.shipped: [OrderStatus.delivered, OrderStatus.cancelled],
    };

    validCases.forEach((from, targets) {
      for (final target in targets) {
        test('${from.name} -> ${target.name} is allowed', () {
          db.addOrder(_buildOrder(id: '#TW1', orderStatus: from));
          final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
          addTearDown(vm.dispose);

          expect(vm.canTransitionTo(target), isTrue);
        });
      }
    });
  });

  group('AdminOrderDetailViewModel - invalid transitions', () {
    test('rejects backward transitions (shipped -> confirmed)', () {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.shipped));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      expect(vm.canTransitionTo(OrderStatus.confirmed), isFalse);
      expect(vm.canTransitionTo(OrderStatus.pending), isFalse);
    });

    test(
      'rejects skipping stages (pending -> shipped, pending -> delivered)',
      () {
        db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));
        final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
        addTearDown(vm.dispose);

        expect(vm.canTransitionTo(OrderStatus.shipped), isFalse);
        expect(vm.canTransitionTo(OrderStatus.delivered), isFalse);
      },
    );

    test('delivered is terminal - no transitions out', () {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.delivered));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      for (final target in OrderStatus.values) {
        if (target == OrderStatus.delivered) continue;
        expect(vm.canTransitionTo(target), isFalse, reason: target.name);
      }
    });

    test('cancelled is terminal - no transitions out', () {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.cancelled));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      for (final target in OrderStatus.values) {
        if (target == OrderStatus.cancelled) continue;
        expect(vm.canTransitionTo(target), isFalse, reason: target.name);
      }
    });
  });

  group('AdminOrderDetailViewModel - confirmation requirement', () {
    test('requires confirmation only for Delivered or Cancelled targets', () {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      vm.stageStatus(OrderStatus.confirmed);
      expect(vm.requiresConfirmation, isFalse);

      vm.stageStatus(OrderStatus.cancelled);
      expect(vm.requiresConfirmation, isTrue);
    });
  });

  group('AdminOrderDetailViewModel - staging and committing', () {
    test('staging an invalid target is ignored', () {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      vm.stageStatus(OrderStatus.delivered); // invalid skip
      expect(vm.stagedStatus, OrderStatus.pending);
      expect(vm.hasPendingChange, isFalse);
    });

    test('a valid staged change commits through the shared database', () async {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      vm.stageStatus(OrderStatus.confirmed);
      expect(vm.hasPendingChange, isTrue);

      final success = await vm.commitStatus();

      expect(success, isTrue);
      expect(db.orders.first.orderStatus, OrderStatus.confirmed);
      expect(vm.order!.orderStatus, OrderStatus.confirmed);
    });

    test(
      'staged state syncs to current state after a successful commit',
      () async {
        db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));
        final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
        addTearDown(vm.dispose);

        vm.stageStatus(OrderStatus.confirmed);
        await vm.commitStatus();

        expect(vm.stagedStatus, OrderStatus.confirmed);
        expect(vm.hasPendingChange, isFalse);
      },
    );

    test('an invalid transition does not mutate the shared database', () async {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.delivered));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      // stageStatus already blocks this, but commitStatus is independently
      // defensive against ever committing an invalid transition.
      final success = await vm.commitStatus();

      expect(success, isFalse);
      expect(db.orders.first.orderStatus, OrderStatus.delivered);
    });

    test('committing with no staged change is a no-op', () async {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      final success = await vm.commitStatus();

      expect(success, isFalse);
      expect(db.orders.first.orderStatus, OrderStatus.pending);
    });
  });

  group('AdminOrderDetailViewModel - shared DB reactivity', () {
    test('an external status change to this order is reflected live', () {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));
      final vm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(vm.dispose);

      db.updateOrderStatus('#TW1', OrderStatus.confirmed);

      expect(vm.order!.orderStatus, OrderStatus.confirmed);
    });
  });

  group('AdminOrderDetailViewModel - cross-feature reactivity regression', () {
    test('a committed status update is immediately reflected in Admin Orders, '
        'Admin Dashboard, and Customer order surfaces through the same '
        'shared MockCommerceDatabase - no manual synchronization', () async {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));

      final detailVm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      final ordersVm = AdminOrdersViewModel(db);
      final dashboardVm = AdminDashboardViewModel(db);
      final customerOrderState = CustomerOrderState(db);
      final myOrdersVm = MyOrdersViewModel(orderState: customerOrderState);
      addTearDown(() {
        detailVm.dispose();
        ordersVm.dispose();
        dashboardVm.dispose();
        myOrdersVm.dispose();
        customerOrderState.dispose();
      });

      final baselinePending = dashboardVm.pendingOrdersCount;

      detailVm.stageStatus(OrderStatus.confirmed);
      final success = await detailVm.commitStatus();

      expect(success, isTrue);
      expect(ordersVm.filteredOrders.first.orderStatus, OrderStatus.confirmed);
      expect(dashboardVm.pendingOrdersCount, baselinePending - 1);
      // MyOrdersViewModel listens to CustomerOrderState and live-updates.
      expect(
        myOrdersVm.orderState.orders.first.orderStatus,
        OrderStatus.confirmed,
      );
      // OrderDetailViewModel (Customer) loads its snapshot once at
      // construction and is not live-reactive by design (unmodified,
      // pre-existing behavior) - a freshly opened one after the update
      // still correctly resolves the new status from the shared source.
      final freshOrderDetailVm = OrderDetailViewModel(
        orderState: customerOrderState,
        orderId: '#TW1',
      );
      addTearDown(freshOrderDetailVm.dispose);
      expect(freshOrderDetailVm.order!.orderStatus, OrderStatus.confirmed);
    });

    test('Payments-tab data is unaffected by an order status update', () async {
      db.addOrder(_buildOrder(id: '#TW1', orderStatus: OrderStatus.pending));
      db.addPayment(
        PaymentRecord(
          paymentId: 'pay_1',
          userId: 'test-uid',
          orderId: '#TW1',
          amount: 1000,
          method: PaymentMethod.stripeCard,
          status: PaymentStatus.paid,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      final detailVm = AdminOrderDetailViewModel(db, orderId: '#TW1');
      addTearDown(detailVm.dispose);

      final paymentsBefore = db.payments.length;
      detailVm.stageStatus(OrderStatus.confirmed);
      await detailVm.commitStatus();

      expect(db.payments.length, paymentsBefore);
      expect(db.payments.first.status, PaymentStatus.paid);
    });
  });
}
