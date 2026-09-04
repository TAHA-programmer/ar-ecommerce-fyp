import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/admin/orders_payments/viewmodels/admin_payments_viewmodel.dart';

OrderModel _buildOrder({
  required String id,
  required String customerName,
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
    orderStatus: OrderStatus.pending,
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

PaymentRecord _buildPayment({
  required String paymentId,
  String orderId = '#TW-default',
  double amount = 1000,
  PaymentStatus status = PaymentStatus.paid,
  DateTime? createdAt,
}) {
  return PaymentRecord(
    paymentId: paymentId,
    userId: 'test-uid',
    orderId: orderId,
    amount: amount,
    method: PaymentMethod.stripeCard,
    status: status,
    createdAt: createdAt ?? DateTime(2026, 1, 1),
  );
}

void main() {
  late MockCommerceDatabase db;
  late AdminPaymentsViewModel viewModel;

  setUp(() {
    db = MockCommerceDatabase();
    viewModel = AdminPaymentsViewModel(db);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('AdminPaymentsViewModel - initial & empty state', () {
    test('starts empty because MockCommerceDatabase seeds no payments', () {
      expect(db.payments, isEmpty);
      expect(viewModel.filteredPayments, isEmpty);
      expect(viewModel.totalPaymentsCount, 0);
      expect(viewModel.paidCount, 0);
      expect(viewModel.pendingCount, 0);
      expect(viewModel.failedCount, 0);
      expect(viewModel.searchQuery, '');
      expect(viewModel.statusFilter, isNull);
    });
  });

  group('AdminPaymentsViewModel - search', () {
    setUp(() {
      db.addOrder(_buildOrder(id: '#TW00000001', customerName: 'Alice Walker'));
      db.addOrder(_buildOrder(id: '#TW00000002', customerName: 'Bob Stone'));
      db.addPayment(
        _buildPayment(paymentId: 'pay_00000001', orderId: '#TW00000001'),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_00000002', orderId: '#TW00000002'),
      );
    });

    test('search matches by payment ID, case-insensitively and trimmed', () {
      viewModel.setSearchQuery('  PAY_00000001  ');
      final results = viewModel.filteredPayments;
      expect(results, hasLength(1));
      expect(results.first.paymentId, 'pay_00000001');
    });

    test('search matches by order ID', () {
      viewModel.setSearchQuery('tw00000002');
      final results = viewModel.filteredPayments;
      expect(results, hasLength(1));
      expect(results.first.orderId, '#TW00000002');
    });

    test('search matches by linked-order customer name', () {
      viewModel.setSearchQuery('bob');
      final results = viewModel.filteredPayments;
      expect(results, hasLength(1));
      expect(results.first.paymentId, 'pay_00000002');
    });
  });

  group('AdminPaymentsViewModel - status filter', () {
    setUp(() {
      for (final status in PaymentStatus.values) {
        db.addPayment(
          _buildPayment(paymentId: 'pay_${status.name}', status: status),
        );
      }
    });

    for (final status in PaymentStatus.values) {
      test('filters to exactly ${status.name} payments', () {
        viewModel.setStatusFilter(status);
        final results = viewModel.filteredPayments;
        expect(results, hasLength(1));
        expect(results.first.status, status);
      });
    }

    test('null resets the status filter back to All', () {
      viewModel.setStatusFilter(PaymentStatus.failed);
      viewModel.setStatusFilter(null);
      expect(
        viewModel.filteredPayments,
        hasLength(PaymentStatus.values.length),
      );
    });
  });

  group('AdminPaymentsViewModel - combined search + filter', () {
    test('search and status filter narrow together', () {
      db.addOrder(_buildOrder(id: '#TW00000001', customerName: 'Alice Walker'));
      db.addOrder(_buildOrder(id: '#TW00000002', customerName: 'Alice Walker'));
      db.addPayment(
        _buildPayment(
          paymentId: 'pay_00000001',
          orderId: '#TW00000001',
          status: PaymentStatus.paid,
        ),
      );
      db.addPayment(
        _buildPayment(
          paymentId: 'pay_00000002',
          orderId: '#TW00000002',
          status: PaymentStatus.failed,
        ),
      );

      viewModel.setSearchQuery('alice');
      viewModel.setStatusFilter(PaymentStatus.failed);

      final results = viewModel.filteredPayments;
      expect(results, hasLength(1));
      expect(results.first.paymentId, 'pay_00000002');
    });
  });

  group('AdminPaymentsViewModel - ordering & reactivity', () {
    test('payments are always newest-first regardless of insertion order', () {
      db.addPayment(
        _buildPayment(paymentId: 'pay_old', createdAt: DateTime(2026, 1, 1)),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_new', createdAt: DateTime(2026, 1, 10)),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_mid', createdAt: DateTime(2026, 1, 5)),
      );

      final results = viewModel.filteredPayments;
      expect(results.map((p) => p.paymentId).toList(), [
        'pay_new',
        'pay_mid',
        'pay_old',
      ]);
    });

    test('a new payment added to the shared MockCommerceDatabase (e.g. by '
        'Customer checkout) appears immediately without manual sync', () {
      expect(viewModel.filteredPayments, isEmpty);

      db.addPayment(_buildPayment(paymentId: 'pay_checkout'));

      expect(viewModel.filteredPayments, hasLength(1));
      expect(viewModel.totalPaymentsCount, 1);
    });
  });

  group('AdminPaymentsViewModel - linked order lookup', () {
    test('resolves the real order when orderId matches', () {
      db.addOrder(_buildOrder(id: '#TW00000001', customerName: 'Alice Walker'));
      final payment = _buildPayment(
        paymentId: 'pay_00000001',
        orderId: '#TW00000001',
      );

      final linked = viewModel.linkedOrderFor(payment);
      expect(linked, isNotNull);
      expect(linked!.deliveryAddress.fullName, 'Alice Walker');
    });

    test('returns null when orderId does not match any order', () {
      final payment = _buildPayment(
        paymentId: 'pay_orphan',
        orderId: '#TW-does-not-exist',
      );
      expect(viewModel.linkedOrderFor(payment), isNull);
    });
  });

  group('AdminPaymentsViewModel - summary counts', () {
    test('total/paid/pending/failed counts are derived from the shared db', () {
      db.addPayment(
        _buildPayment(paymentId: 'pay_1', status: PaymentStatus.paid),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_2', status: PaymentStatus.paid),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_3', status: PaymentStatus.pending),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_4', status: PaymentStatus.failed),
      );

      expect(viewModel.totalPaymentsCount, 4);
      expect(viewModel.paidCount, 2);
      expect(viewModel.pendingCount, 1);
      expect(viewModel.failedCount, 1);
    });
  });
}
