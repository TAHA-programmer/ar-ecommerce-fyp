import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/utils/currency_formatter.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/admin/orders_payments/widgets/admin_order_card.dart';
import 'package:twin_ar/features/admin/views/admin_orders_view.dart';
import 'package:twin_ar/features/admin/widgets/admin_bottom_navigation.dart';

OrderModel _buildOrder({
  required String id,
  required String customerName,
  required DateTime orderDate,
  OrderStatus orderStatus = OrderStatus.pending,
  PaymentStatus paymentStatus = PaymentStatus.paid,
  double total = 4500,
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

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CommerceDatabase>.value(value: db),
        ChangeNotifierProvider<AuthSessionState>(
          create: (_) => AuthSessionState(),
        ),
      ],
      child: MaterialApp(
        home: const Scaffold(body: AdminOrdersView()),
        onGenerateRoute: (settings) {
          if (settings.name == RouteNames.adminOrderDetail) {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => Scaffold(
                body: Text('Admin Order Detail Stub: ${settings.arguments}'),
              ),
            );
          }
          return null;
        },
      ),
    );
  }

  setUp(() {
    db = MockCommerceDatabase();
  });

  group('AdminOrdersView', () {
    testWidgets('replaces the placeholder with the real screen', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Orders & Payments'), findsOneWidget);
      expect(
        find.text('Orders & Payments will be implemented later.'),
        findsNothing,
      );
    });

    testWidgets('shows the Orders tab selected in the Admin bottom nav', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final nav = tester.widget<AdminBottomNavigation>(
        find.byType(AdminBottomNavigation),
      );
      expect(nav.currentIndex, 3);
    });

    testWidgets('shows "No orders yet" when the shared database is empty', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.byType(AdminOrderCard), findsNothing);
    });

    testWidgets('renders order cards sourced from the shared database', (
      tester,
    ) async {
      db.addOrder(
        _buildOrder(
          id: '#TW00000001',
          customerName: 'Alice Walker',
          orderDate: DateTime(2026, 1, 1),
          orderStatus: OrderStatus.shipped,
          paymentStatus: PaymentStatus.paid,
          total: 4500,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final card = find.byType(AdminOrderCard);
      expect(card, findsOneWidget);
      expect(find.text('#TW00000001'), findsOneWidget);
      expect(find.text('Alice Walker'), findsOneWidget);
      expect(find.text(CurrencyFormatter.format(4500)), findsOneWidget);
      // Scoped to the card since "Paid"/"Shipped" also label filter chips.
      expect(
        find.descendant(of: card, matching: find.text('Stripe')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Paid')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.text('Shipped')),
        findsOneWidget,
      );
      // The Figma sample used $ and COD; neither must ever appear.
      expect(find.textContaining('\$'), findsNothing);
      expect(find.text('COD'), findsNothing);
    });

    testWidgets('orders render newest-first', (tester) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 1200));

      db.addOrder(
        _buildOrder(
          id: '#TW-old',
          customerName: 'Old Customer',
          orderDate: DateTime(2026, 1, 1),
        ),
      );
      db.addOrder(
        _buildOrder(
          id: '#TW-new',
          customerName: 'New Customer',
          orderDate: DateTime(2026, 1, 10),
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final idTexts = tester
          .widgetList<Text>(find.textContaining('#TW-'))
          .map((t) => t.data)
          .toList();
      expect(idTexts.indexOf('#TW-new'), lessThan(idTexts.indexOf('#TW-old')));
    });

    testWidgets('search narrows results and shows "No orders found"', (
      tester,
    ) async {
      db.addOrder(
        _buildOrder(
          id: '#TW00000001',
          customerName: 'Alice Walker',
          orderDate: DateTime(2026, 1, 1),
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('admin_orders_search_field')),
        'no-such-order-xyz',
      );
      await tester.pumpAndSettle();

      expect(find.text('No orders found'), findsOneWidget);
      expect(find.byType(AdminOrderCard), findsNothing);
    });

    testWidgets('order-status filter narrows the visible cards', (
      tester,
    ) async {
      db.addOrder(
        _buildOrder(
          id: '#TW-shipped',
          customerName: 'Shipped Customer',
          orderDate: DateTime(2026, 1, 1),
          orderStatus: OrderStatus.shipped,
        ),
      );
      db.addOrder(
        _buildOrder(
          id: '#TW-pending',
          customerName: 'Pending Customer',
          orderDate: DateTime(2026, 1, 2),
          orderStatus: OrderStatus.pending,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('order_status_filter_shipped')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOrderCard), findsOneWidget);
      expect(find.text('#TW-shipped'), findsOneWidget);
    });

    testWidgets('payment-status filter narrows the visible cards', (
      tester,
    ) async {
      db.addOrder(
        _buildOrder(
          id: '#TW-paid',
          customerName: 'Paid Customer',
          orderDate: DateTime(2026, 1, 1),
          paymentStatus: PaymentStatus.paid,
        ),
      );
      db.addOrder(
        _buildOrder(
          id: '#TW-failed',
          customerName: 'Failed Customer',
          orderDate: DateTime(2026, 1, 2),
          paymentStatus: PaymentStatus.failed,
        ),
      );

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('payment_status_filter_failed')));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOrderCard), findsOneWidget);
      expect(find.text('#TW-failed'), findsOneWidget);
    });

    testWidgets(
      'the Admin Orders screen reacts automatically when Customer checkout '
      'adds a new order to the shared database',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.text('No orders yet'), findsOneWidget);

        db.addOrder(
          _buildOrder(
            id: '#TW-fresh',
            customerName: 'Fresh Customer',
            orderDate: DateTime(2026, 1, 1),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('No orders yet'), findsNothing);
        expect(find.byType(AdminOrderCard), findsOneWidget);
        expect(find.text('#TW-fresh'), findsOneWidget);
      },
    );

    testWidgets(
      'View Details navigates to Admin Order Detail with the correct orderId',
      (tester) async {
        db.addOrder(
          _buildOrder(
            id: '#TW00000001',
            customerName: 'Alice Walker',
            orderDate: DateTime(2026, 1, 1),
          ),
        );

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.tap(find.text('View Details'));
        await tester.pumpAndSettle();

        expect(
          find.text('Admin Order Detail Stub: #TW00000001'),
          findsOneWidget,
        );
        expect(find.byType(AdminOrderCard), findsNothing);
      },
    );

    testWidgets(
      'the Orders/Payments selector switches away from Orders content and '
      'back without touching the Orders tab itself',
      (tester) async {
        db.addOrder(
          _buildOrder(
            id: '#TW00000001',
            customerName: 'Alice Walker',
            orderDate: DateTime(2026, 1, 1),
          ),
        );

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        expect(find.byType(AdminOrderCard), findsOneWidget);

        await tester.tap(find.byKey(const Key('admin_orders_mode_payments')));
        await tester.pumpAndSettle();

        // The Orders content (and the now-superseded Payments placeholder)
        // are both gone - the real Payments tab has replaced it.
        expect(find.byType(AdminOrderCard), findsNothing);
        expect(find.text('Coming Soon'), findsNothing);
        expect(
          find.text('Track transactions and payment status'),
          findsOneWidget,
        );

        await tester.tap(find.byKey(const Key('admin_orders_mode_orders')));
        await tester.pumpAndSettle();

        expect(find.byType(AdminOrderCard), findsOneWidget);
      },
    );
  });
}
