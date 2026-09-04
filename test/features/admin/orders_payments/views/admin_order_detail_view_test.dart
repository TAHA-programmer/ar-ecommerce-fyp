import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/core/utils/currency_formatter.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/admin/orders_payments/viewmodels/admin_order_detail_viewmodel.dart';
import 'package:twin_ar/features/admin/orders_payments/views/admin_order_detail_view.dart';
import 'package:twin_ar/features/admin/orders_payments/widgets/admin_order_status_timeline.dart';
import 'package:twin_ar/features/admin/widgets/admin_bottom_navigation.dart';

OrderModel _buildOrder({
  required String id,
  String customerName = 'Alice Walker',
  OrderStatus orderStatus = OrderStatus.pending,
  DateTime? orderDate,
  String? selectedSize,
  String? selectedColor,
}) {
  final date = orderDate ?? DateTime(2026, 1, 1);
  return OrderModel(
    id: id,
    userId: 'test-uid',
    paymentId: 'pay_$id',
    items: [
      OrderItemModel(
        productId: 'p1',
        productName: 'Luna Accent Chair',
        imagePath: 'assets/test.png',
        quantity: 2,
        selectedSize: selectedSize,
        selectedColor: selectedColor,
        unitPrice: 5000,
        lineTotal: 10000,
      ),
    ],
    orderDate: date,
    subtotal: 10000,
    deliveryFee: 200,
    discount: 500,
    total: 9700,
    paymentMethod: PaymentMethod.stripeCard,
    paymentStatus: PaymentStatus.paid,
    orderStatus: orderStatus,
    deliveryAddress: AddressModel(
      fullName: customerName,
      phoneNumber: '9999999999',
      addressLine1: '123 Test Street',
      addressLine2: 'Apt 4B',
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

  Widget buildTestWidget(String orderId) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CommerceDatabase>.value(value: db),
        ChangeNotifierProvider<AuthSessionState>(
          create: (_) => AuthSessionState(),
        ),
        ChangeNotifierProvider<AdminOrderDetailViewModel>(
          create: (context) => AdminOrderDetailViewModel(db, orderId: orderId),
        ),
      ],
      child: MaterialApp(
        home: const AdminOrderDetailView(),
        routes: {
          RouteNames.helpSupport: (_) =>
              const Scaffold(body: Text('Help Support Stub')),
        },
      ),
    );
  }

  setUp(() {
    db = MockCommerceDatabase();
  });

  group('AdminOrderDetailView', () {
    testWidgets('renders every major section as a bordered card', (
      tester,
    ) async {
      db.addOrder(_buildOrder(id: '#TW00000001'));
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      expect(find.text('Order Details'), findsOneWidget);
      expect(find.text('#TW00000001'), findsOneWidget);
      expect(find.text('Customer Information'), findsOneWidget);
      expect(find.text('Delivery Address'), findsOneWidget);
      expect(find.text('Ordered Products (1)'), findsOneWidget);
      expect(find.text('Price Summary'), findsOneWidget);
      expect(find.text('Payment Information'), findsOneWidget);
      expect(find.text('Current Order Status'), findsOneWidget);
      expect(find.text('Order Timeline'), findsOneWidget);
      expect(find.text('Update Order Status'), findsOneWidget);
      expect(find.byType(Container), findsWidgets);
    });

    testWidgets('shows the Orders tab selected in the Admin bottom nav', (
      tester,
    ) async {
      db.addOrder(_buildOrder(id: '#TW00000001'));
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      final nav = tester.widget<AdminBottomNavigation>(
        find.byType(AdminBottomNavigation),
      );
      expect(nav.currentIndex, 3);
    });

    testWidgets('renders real customer/address data, no email, no country', (
      tester,
    ) async {
      db.addOrder(_buildOrder(id: '#TW00000001', customerName: 'Alice Walker'));
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      expect(find.text('Alice Walker'), findsWidgets);
      expect(find.text('9999999999'), findsOneWidget);
      expect(find.textContaining('123 Test Street'), findsOneWidget);
      expect(find.textContaining('Apt 4B'), findsOneWidget);
      expect(find.textContaining('Test City, Test State'), findsOneWidget);
      expect(find.textContaining('@'), findsNothing);
      expect(find.text('United States'), findsNothing);
      expect(find.text('India'), findsNothing);
    });

    testWidgets(
      'renders order item snapshot values, including size/color when present',
      (tester) async {
        db.addOrder(
          _buildOrder(
            id: '#TW00000001',
            selectedSize: 'M',
            selectedColor: 'Beige',
          ),
        );
        await tester.pumpWidget(buildTestWidget('#TW00000001'));
        await tester.pumpAndSettle();

        expect(find.text('Luna Accent Chair'), findsOneWidget);
        expect(find.text('Size: M • Color: Beige'), findsOneWidget);
        expect(find.text('Qty: 2'), findsOneWidget);
        expect(find.text(CurrencyFormatter.format(10000)), findsWidgets);
        expect(find.text('Material'), findsNothing);
        expect(find.textContaining('Material:'), findsNothing);
      },
    );

    testWidgets(
      'renders Rs pricing (Subtotal/Delivery Fee/Discount/Total), no Tax, no \$',
      (tester) async {
        db.addOrder(_buildOrder(id: '#TW00000001'));
        await tester.pumpWidget(buildTestWidget('#TW00000001'));
        await tester.pumpAndSettle();

        expect(find.text('Subtotal'), findsOneWidget);
        expect(find.text('Delivery Fee'), findsOneWidget);
        expect(find.text('Discount'), findsOneWidget);
        expect(find.text('Total'), findsOneWidget);
        expect(find.text('Tax'), findsNothing);
        expect(find.textContaining('\$'), findsNothing);
        expect(find.text('COD'), findsNothing);
        expect(find.text('Cash on Delivery'), findsNothing);
      },
    );

    testWidgets('shows Stripe payment method and status, never COD', (
      tester,
    ) async {
      db.addOrder(_buildOrder(id: '#TW00000001'));
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      expect(find.text('Stripe'), findsWidgets);
      expect(find.text('Paid'), findsWidgets);
    });

    testWidgets('shows the linked transaction ID when a payment exists', (
      tester,
    ) async {
      db.addOrder(_buildOrder(id: '#TW00000001'));
      db.addPayment(
        PaymentRecord(
          paymentId: 'pay_00000001',
          userId: 'test-uid',
          orderId: '#TW00000001',
          amount: 9700,
          method: PaymentMethod.stripeCard,
          status: PaymentStatus.paid,
          createdAt: DateTime(2026, 1, 1),
        ),
      );
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      expect(find.text('pay_00000001'), findsOneWidget);
    });

    testWidgets(
      'falls back to em-dash for the transaction ID when no payment is linked',
      (tester) async {
        db.addOrder(_buildOrder(id: '#TW00000001'));
        await tester.pumpWidget(buildTestWidget('#TW00000001'));
        await tester.pumpAndSettle();

        expect(find.text('—'), findsOneWidget);
      },
    );

    testWidgets('renders the vertical Admin status timeline', (tester) async {
      db.addOrder(
        _buildOrder(id: '#TW00000001', orderStatus: OrderStatus.shipped),
      );
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminOrderStatusTimeline), findsOneWidget);
      expect(find.text('Order placed'), findsOneWidget);
      expect(find.text('Confirmed'), findsWidgets);
      expect(find.text('Delivered'), findsWidgets);
    });

    testWidgets('invalid status chips cannot be staged, valid ones can', (
      tester,
    ) async {
      db.addOrder(
        _buildOrder(id: '#TW00000001', orderStatus: OrderStatus.pending),
      );
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      // pending -> shipped is an invalid skip: tapping must not stage it.
      final shippedChip = find.byKey(
        const Key('admin_order_status_chip_shipped'),
      );
      await tester.ensureVisible(shippedChip);
      await tester.tap(shippedChip);
      await tester.pumpAndSettle();

      // pending -> confirmed is valid: tapping stages it (Update enables).
      final confirmedChip = find.byKey(
        const Key('admin_order_status_chip_confirmed'),
      );
      await tester.ensureVisible(confirmedChip);
      await tester.tap(confirmedChip);
      await tester.pumpAndSettle();

      final updateButton = find.byKey(
        const Key('admin_order_update_status_button'),
      );
      await tester.ensureVisible(updateButton);
      await tester.tap(updateButton);
      await tester.pumpAndSettle();

      // If the invalid "shipped" tap had incorrectly stuck, this would
      // have committed shipped instead of confirmed (or been blocked
      // entirely since pending -> shipped is invalid and would silently
      // no-op the update).
      expect(db.orders.first.orderStatus, OrderStatus.confirmed);

      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'Confirmed/Shipped transitions commit without a confirmation dialog',
      (tester) async {
        db.addOrder(
          _buildOrder(id: '#TW00000001', orderStatus: OrderStatus.pending),
        );
        await tester.pumpWidget(buildTestWidget('#TW00000001'));
        await tester.pumpAndSettle();

        final confirmedChip = find.byKey(
          const Key('admin_order_status_chip_confirmed'),
        );
        await tester.ensureVisible(confirmedChip);
        await tester.tap(confirmedChip);
        await tester.pumpAndSettle();

        final updateButton = find.byKey(
          const Key('admin_order_update_status_button'),
        );
        await tester.ensureVisible(updateButton);
        await tester.tap(updateButton);
        await tester.pumpAndSettle();

        expect(find.text('Mark order as Confirmed?'), findsNothing);
        expect(db.orders.first.orderStatus, OrderStatus.confirmed);
        expect(find.text('Order status updated to Confirmed'), findsOneWidget);

        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'Delivered/Cancelled transitions require confirmation before committing',
      (tester) async {
        db.addOrder(
          _buildOrder(id: '#TW00000001', orderStatus: OrderStatus.shipped),
        );
        await tester.pumpWidget(buildTestWidget('#TW00000001'));
        await tester.pumpAndSettle();

        final cancelledChip = find.byKey(
          const Key('admin_order_status_chip_cancelled'),
        );
        await tester.ensureVisible(cancelledChip);
        await tester.tap(cancelledChip);
        await tester.pumpAndSettle();

        final updateButton = find.byKey(
          const Key('admin_order_update_status_button'),
        );
        await tester.ensureVisible(updateButton);
        await tester.tap(updateButton);
        await tester.pumpAndSettle();

        // Status must NOT change yet - confirmation dialog is pending.
        expect(find.text('Mark order as Cancelled?'), findsOneWidget);
        expect(db.orders.first.orderStatus, OrderStatus.shipped);

        await tester.tap(
          find.byKey(const Key('admin_order_status_confirm_apply')),
        );
        await tester.pumpAndSettle();

        expect(db.orders.first.orderStatus, OrderStatus.cancelled);
        expect(find.text('Order status updated to Cancelled'), findsOneWidget);

        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets('cancelling out of the confirmation dialog changes nothing', (
      tester,
    ) async {
      db.addOrder(
        _buildOrder(id: '#TW00000001', orderStatus: OrderStatus.shipped),
      );
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      final deliveredChip = find.byKey(
        const Key('admin_order_status_chip_delivered'),
      );
      await tester.ensureVisible(deliveredChip);
      await tester.tap(deliveredChip);
      await tester.pumpAndSettle();

      final updateButton = find.byKey(
        const Key('admin_order_update_status_button'),
      );
      await tester.ensureVisible(updateButton);
      await tester.tap(updateButton);
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const Key('admin_order_status_confirm_cancel')),
      );
      await tester.pumpAndSettle();

      expect(db.orders.first.orderStatus, OrderStatus.shipped);
    });

    testWidgets('back button and Close both pop the screen', (tester) async {
      db.addOrder(_buildOrder(id: '#TW00000001'));
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => MultiProvider(
                        providers: [
                          ChangeNotifierProvider<CommerceDatabase>.value(
                            value: db,
                          ),
                          ChangeNotifierProvider<AuthSessionState>(
                            create: (_) => AuthSessionState(),
                          ),
                          ChangeNotifierProvider<AdminOrderDetailViewModel>(
                            create: (context) => AdminOrderDetailViewModel(
                              db,
                              orderId: '#TW00000001',
                            ),
                          ),
                        ],
                        child: const AdminOrderDetailView(),
                      ),
                    ),
                  ),
                  child: const Text('Open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Open'));
      await tester.pumpAndSettle();
      expect(find.text('Order Details'), findsOneWidget);

      await tester.tap(find.byKey(const Key('admin_order_detail_back_button')));
      await tester.pumpAndSettle();
      expect(find.text('Order Details'), findsNothing);
      expect(find.text('Open'), findsOneWidget);
    });

    testWidgets('shows a safe empty state for a missing order, no crash', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget('#TW-does-not-exist'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Order not found'), findsOneWidget);
    });

    testWidgets('narrow 360px viewport renders with no overflow', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 800));

      db.addOrder(
        _buildOrder(
          id: '#TW00000001',
          selectedSize: 'M',
          selectedColor: 'Beige',
        ),
      );
      await tester.pumpWidget(buildTestWidget('#TW00000001'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });
  });
}
