import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/core/utils/currency_formatter.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/admin/orders_payments/widgets/admin_order_card.dart';
import 'package:twin_ar/features/admin/orders_payments/widgets/admin_payment_card.dart';
import 'package:twin_ar/features/admin/views/admin_orders_view.dart';

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
  double amount = 4500,
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

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CommerceDatabase>.value(value: db),
        ChangeNotifierProvider<AuthSessionState>(
          create: (_) => AuthSessionState(),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: AdminOrdersView())),
    );
  }

  Future<void> switchToPayments(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('admin_orders_mode_payments')));
    await tester.pumpAndSettle();
  }

  setUp(() {
    db = MockCommerceDatabase();
  });

  group('Admin Payments tab (via AdminOrdersView)', () {
    testWidgets('switching Orders -> Payments replaces the placeholder', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await switchToPayments(tester);

      expect(find.text('Coming Soon'), findsNothing);
      expect(
        find.text('Track transactions and payment status'),
        findsOneWidget,
      );
    });

    testWidgets('the Orders tab still works after Payments is wired in', (
      tester,
    ) async {
      db.addOrder(_buildOrder(id: '#TW00000001', customerName: 'Alice Walker'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(
        find.text('Manage customer orders and payment activity'),
        findsOneWidget,
      );
      expect(find.byType(AdminOrderCard), findsOneWidget);
      expect(find.text('#TW00000001'), findsOneWidget);
    });

    testWidgets('shows "No payments yet" when the shared database is empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await switchToPayments(tester);

      expect(find.text('No payments yet'), findsOneWidget);
      expect(find.byType(AdminPaymentCard), findsNothing);
    });

    testWidgets('renders real PaymentRecord values, Stripe only, Rs only', (
      tester,
    ) async {
      db.addOrder(_buildOrder(id: '#TW00000001', customerName: 'Alice Walker'));
      db.addPayment(
        _buildPayment(
          paymentId: 'pay_00000001',
          orderId: '#TW00000001',
          amount: 4500,
          status: PaymentStatus.paid,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await switchToPayments(tester);

      final card = find.byType(AdminPaymentCard);
      expect(card, findsOneWidget);
      expect(find.text('pay_00000001'), findsOneWidget);
      expect(find.text('Order: #TW00000001'), findsOneWidget);
      expect(find.text('Customer: Alice Walker'), findsOneWidget);
      expect(find.text(CurrencyFormatter.format(4500)), findsOneWidget);
      expect(
        find.descendant(of: card, matching: find.text('Stripe')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Paid')),
        findsOneWidget,
      );

      // Real-data-only guarantees.
      expect(find.textContaining('\$'), findsNothing);
      expect(find.text('COD'), findsNothing);
      expect(find.text('Cash on Delivery'), findsNothing);
      expect(find.text('Processing'), findsNothing);
      expect(find.text('Cancelled'), findsNothing);
      expect(find.text('Refunded'), findsNothing);
    });

    testWidgets(
      'a payment with an unresolvable order renders the safe fallback',
      (tester) async {
        db.addPayment(
          _buildPayment(paymentId: 'pay_orphan', orderId: '#TW-does-not-exist'),
        );

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();
        await switchToPayments(tester);

        expect(find.text('Order: —'), findsOneWidget);
        expect(find.text('Customer: —'), findsOneWidget);
      },
    );

    testWidgets('payments render newest-first', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 1200));

      db.addPayment(
        _buildPayment(paymentId: 'pay_old', createdAt: DateTime(2026, 1, 1)),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_new', createdAt: DateTime(2026, 1, 10)),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await switchToPayments(tester);

      final idTexts = tester
          .widgetList<Text>(find.textContaining('pay_'))
          .map((t) => t.data)
          .toList();
      expect(idTexts.indexOf('pay_new'), lessThan(idTexts.indexOf('pay_old')));
    });

    testWidgets('search narrows results and shows "No payments found"', (
      tester,
    ) async {
      db.addPayment(_buildPayment(paymentId: 'pay_00000001'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await switchToPayments(tester);

      await tester.enterText(
        find.byKey(const Key('admin_payments_search_field')),
        'no-such-payment-xyz',
      );
      await tester.pumpAndSettle();

      expect(find.text('No payments found'), findsOneWidget);
      expect(find.byType(AdminPaymentCard), findsNothing);
    });

    testWidgets('status filter narrows the visible cards', (tester) async {
      db.addPayment(
        _buildPayment(paymentId: 'pay_paid', status: PaymentStatus.paid),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_failed', status: PaymentStatus.failed),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await switchToPayments(tester);

      await tester.tap(
        find.byKey(const Key('payments_tab_status_filter_failed')),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AdminPaymentCard), findsOneWidget);
      expect(find.text('pay_failed'), findsOneWidget);
    });

    testWidgets('summary strip shows real counts derived from the shared db', (
      tester,
    ) async {
      db.addPayment(
        _buildPayment(paymentId: 'pay_1', status: PaymentStatus.paid),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_2', status: PaymentStatus.pending),
      );
      db.addPayment(
        _buildPayment(paymentId: 'pay_3', status: PaymentStatus.failed),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();
      await switchToPayments(tester);

      expect(find.textContaining('Total Payments'), findsOneWidget);
      expect(find.text('3'), findsOneWidget); // Total Payments count
      expect(find.text('1'), findsWidgets); // Paid/Pending/Failed each = 1
    });

    testWidgets(
      'a no-match search under a squeezed (keyboard-open) viewport does not '
      'overflow',
      (tester) async {
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(const Size(360, 500));

        db.addPayment(_buildPayment(paymentId: 'pay_00000001'));

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();
        await switchToPayments(tester);

        await tester.enterText(
          find.byKey(const Key('admin_payments_search_field')),
          'no-such-payment-xyz',
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('No payments found'), findsOneWidget);
      },
    );
  });
}
