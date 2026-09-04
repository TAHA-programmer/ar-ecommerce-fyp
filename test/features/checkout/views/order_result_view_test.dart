import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/customer_order_state.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/checkout/views/order_result_view.dart';

void main() {
  late CustomerOrderState orderState;
  late OrderModel testOrder;

  setUp(() {
    final db = MockCommerceDatabase();
    orderState = CustomerOrderState(db);

    testOrder = OrderModel(
      id: '#TW12345678',
      userId: 'test-uid',
      paymentId: 'pay_12345678',
      items: [
        OrderItemModel(
          productId: '1',
          productName: 'Test Product',
          imagePath: 'assets/images/test.png',
          quantity: 2,
          unitPrice: 5000.0,
          lineTotal: 10000.0,
        ),
      ],
      orderDate: DateTime.now(),
      subtotal: 10000.0,
      deliveryFee: 500.0,
      discount: 0.0,
      total: 10500.0,
      paymentMethod: PaymentMethod.stripeCard,
      paymentStatus: PaymentStatus.paid,
      orderStatus: OrderStatus.pending,
      deliveryAddress: AddressModel(
        fullName: 'Test User',
        phoneNumber: '1234567890',
        addressLine1: '123 Test St',
        city: 'Test City',
        provinceOrState: 'Test State',
        postalCode: '12345',
      ),
      estimatedDeliveryStart: DateTime.now().add(const Duration(days: 7)),
      estimatedDeliveryEnd: DateTime.now().add(const Duration(days: 14)),
    );

    // Mock-only fixture helper (not part of the CommerceDatabase interface -
    // see MockCommerceDatabase.addOrder's doc comment).
    db.addOrder(testOrder);
  });

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [ChangeNotifierProvider.value(value: orderState)],
      child: MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name == RouteNames.home) {
            return MaterialPageRoute(
              builder: (_) => const Scaffold(body: Text('Home Screen')),
            );
          }
          if (settings.name == RouteNames.orderDetail) {
            final args = settings.arguments as String?;
            return MaterialPageRoute(
              builder: (_) => Scaffold(body: Text('Order Detail: $args')),
            );
          }
          return null;
        },
        home: OrderResultView(orderId: testOrder.id),
      ),
    );
  }

  group('OrderResultView Tests', () {
    testWidgets('renders success UI with correct details', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      // Image
      expect(find.byType(Image), findsOneWidget);

      // Texts
      expect(find.text('Order Placed Successfully'), findsOneWidget);
      expect(find.text('Order ID'), findsOneWidget);
      expect(find.text('#TW12345678'), findsOneWidget);
      expect(find.text('Amount'), findsOneWidget);
      expect(find.text('Rs 10,500/-'), findsOneWidget);
      expect(find.text('Payment Method'), findsOneWidget);
      expect(find.text('Stripe / Card'), findsOneWidget);
      expect(find.text('Payment Status'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);

      // Buttons
      expect(find.text('Continue Shopping'), findsOneWidget);
      expect(find.text('Track Order'), findsOneWidget);
    });

    testWidgets(
      'a long webhook-generated order id is shortened and does not overflow',
      (tester) async {
        final db = MockCommerceDatabase();
        final state = CustomerOrderState(db);
        const longId = 'ord_a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4';
        db.addOrder(
          OrderModel(
            id: longId,
            userId: 'test-uid',
            paymentId: 'pay_a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4',
            items: testOrder.items,
            orderDate: testOrder.orderDate,
            subtotal: testOrder.subtotal,
            deliveryFee: testOrder.deliveryFee,
            discount: testOrder.discount,
            total: testOrder.total,
            paymentMethod: PaymentMethod.stripeCard,
            paymentStatus: PaymentStatus.paid,
            orderStatus: OrderStatus.pending,
            deliveryAddress: testOrder.deliveryAddress,
            estimatedDeliveryStart: testOrder.estimatedDeliveryStart,
            estimatedDeliveryEnd: testOrder.estimatedDeliveryEnd,
          ),
        );

        await tester.pumpWidget(
          MultiProvider(
            providers: [ChangeNotifierProvider.value(value: state)],
            child: const MaterialApp(home: OrderResultView(orderId: longId)),
          ),
        );

        // Shortened, not the raw 44-char id (widget tests also fail on overflow).
        expect(find.text('#A1B2C3D4'), findsOneWidget);
        expect(find.text(longId), findsNothing);
      },
    );

    testWidgets('Continue Shopping navigates to Home', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final continueBtn = find.widgetWithText(
        ElevatedButton,
        'Continue Shopping',
      );
      await tester.ensureVisible(continueBtn);
      await tester.tap(continueBtn);
      await tester.pumpAndSettle();

      expect(find.text('Home Screen'), findsOneWidget);
    });
    testWidgets('Track Order navigates to Order Detail', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      final trackOrderBtn = find.widgetWithText(OutlinedButton, 'Track Order');
      await tester.ensureVisible(trackOrderBtn);
      await tester.tap(trackOrderBtn);
      await tester.pumpAndSettle();

      expect(find.text('Order Detail: #TW12345678'), findsOneWidget);
    });
  });
}
