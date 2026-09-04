import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/customer_order_state.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/orders/viewmodels/order_detail_viewmodel.dart';
import 'package:twin_ar/features/orders/views/order_detail_view.dart';
import 'package:twin_ar/features/orders/views/widgets/order_status_timeline.dart';

void main() {
  group('OrderDetailView Tests', () {
    late MockCommerceDatabase db;
    late CustomerOrderState orderState;
    late OrderModel mockOrder;

    setUp(() {
      db = MockCommerceDatabase();
      orderState = CustomerOrderState(db);
      mockOrder = OrderModel(
        id: '#TW12345678', // One hash already
        userId: 'test-uid',
        paymentId: 'pay_12345678',
        items: [
          OrderItemModel(
            productId: 'p1',
            productName: 'Men\'s Oxford Shirt',
            imagePath: 'assets/images/products/shirt.png',
            selectedSize: 'M',
            selectedColor: 'Blue',
            quantity: 2,
            unitPrice: 5000,
            lineTotal: 10000,
          ),
        ],
        orderDate: DateTime(2024, 5, 24, 10, 32),
        subtotal: 10000,
        deliveryFee: 500,
        discount: 1000,
        total: 9500,
        paymentMethod: PaymentMethod.stripeCard,
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.confirmed,
        deliveryAddress: AddressModel(
          id: 'A1',
          fullName: 'Ananya Sharma',
          phoneNumber: '1234567890',
          addressLine1: '12, Greenwood Apartments',
          city: 'Bengaluru',
          provinceOrState: 'Karnataka',
          postalCode: '560001',
        ),
        estimatedDeliveryStart: DateTime(2024),
        estimatedDeliveryEnd: DateTime(2024),
      );
      db.addOrder(mockOrder);
    });

    Widget createWidgetUnderTest({
      String orderId = '#TW12345678',
      Size size = const Size(400, 800),
    }) {
      return MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return MediaQuery(
                data: MediaQuery.of(context).copyWith(size: size),
                child: ChangeNotifierProvider(
                  create: (_) => OrderDetailViewModel(
                    orderState: orderState,
                    orderId: orderId,
                  ),
                  child: const OrderDetailView(),
                ),
              );
            },
          ),
        ),
        routes: {
          RouteNames.home: (_) => const Scaffold(body: Text('Home')),
          RouteNames.helpSupport: (_) =>
              const Scaffold(body: Text('Help & Support')),
        },
      );
    }

    testWidgets('Displays missing order state for invalid ID', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest(orderId: 'INVALID'));
      await tester.pumpAndSettle();

      expect(find.text('Order Not Found'), findsOneWidget);
      expect(
        find.text('We couldn\'t find the details for this order.'),
        findsOneWidget,
      );
    });

    testWidgets('Displays correct order details', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      // Order Meta
      expect(find.text('Order Details'), findsOneWidget);
      expect(find.text('#TW12345678'), findsOneWidget); // Only one hash
      expect(find.text('May 24, 2024 • 10:32 AM'), findsOneWidget);

      // Items
      expect(find.text('Ordered Products (1)'), findsOneWidget);
      expect(find.text('Men\'s Oxford Shirt'), findsOneWidget);
      expect(find.text('Size: M • Color: Blue'), findsOneWidget);
      expect(find.text('Qty: 2'), findsOneWidget);
      expect(
        find.text('Rs 10,000'),
        findsWidgets,
      ); // Rs format for item and subtotal

      // No View Receipt
      expect(find.text('View Receipt'), findsNothing);

      // Address
      expect(find.text('Ananya Sharma'), findsOneWidget);
      expect(find.textContaining('Greenwood Apartments'), findsOneWidget);

      // Payment
      expect(find.text('Stripe'), findsOneWidget);
      expect(find.text('Paid'), findsOneWidget);
      expect(find.text('UPI'), findsNothing);
      expect(find.text('COD'), findsNothing);

      // Summary
      expect(find.text('Rs 9,500'), findsOneWidget); // Total
    });

    testWidgets('Timeline renders correctly for all statuses', (tester) async {
      final statuses = [
        OrderStatus.pending,
        OrderStatus.confirmed,
        OrderStatus.shipped,
        OrderStatus.delivered,
        OrderStatus.cancelled,
      ];

      for (var status in statuses) {
        final order = OrderModel(
          id: 'test_$status',
          userId: 'test-uid',
          paymentId: 'pay_test_$status',
          items: [],
          orderDate: DateTime.now(),
          subtotal: 0,
          deliveryFee: 0,
          discount: 0,
          total: 0,
          paymentMethod: PaymentMethod.stripeCard,
          paymentStatus: PaymentStatus.paid,
          orderStatus: status,
          deliveryAddress: AddressModel(
            id: '',
            fullName: '',
            phoneNumber: '',
            addressLine1: '',
            city: '',
            provinceOrState: '',
            postalCode: '',
          ),
          estimatedDeliveryStart: DateTime.now(),
          estimatedDeliveryEnd: DateTime.now(),
        );
        db.addOrder(order);

        await tester.pumpWidget(createWidgetUnderTest(orderId: 'test_$status'));
        await tester.pumpAndSettle();

        expect(find.byType(OrderStatusTimeline), findsOneWidget);
        expect(find.byType(OrderStatusTimeline), findsOneWidget);
      }
    });

    testWidgets('Contact Support navigates correctly', (tester) async {
      await tester.pumpWidget(createWidgetUnderTest());
      await tester.pumpAndSettle();

      final btn = find.widgetWithText(ElevatedButton, 'Contact Support').first;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();

      expect(find.text('Help & Support'), findsOneWidget);
    });

    testWidgets('Continue Shopping navigates to Home', (tester) async {
      // Need a test setup with multiple routes pushed to verify popUntil
      await tester.pumpWidget(
        MaterialApp(
          initialRoute: '/',
          routes: {
            '/': (_) => const Scaffold(body: Text('Root')),
            RouteNames.home: (_) => const Scaffold(body: Text('Home')),
            RouteNames.orderDetail: (_) => Builder(
              builder: (context) {
                return ChangeNotifierProvider(
                  create: (_) => OrderDetailViewModel(
                    orderState: orderState,
                    orderId: '#TW12345678',
                  ),
                  child: const OrderDetailView(),
                );
              },
            ),
          },
        ),
      );
      await tester.pumpAndSettle();

      // Push to order detail
      final BuildContext context = tester.element(find.text('Root'));
      Navigator.pushNamed(context, RouteNames.orderDetail);
      await tester.pumpAndSettle();

      expect(find.text('Order Details'), findsOneWidget);

      final btn = find
          .widgetWithText(OutlinedButton, 'Continue Shopping')
          .first;
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -500),
      );
      await tester.pumpAndSettle();
      await tester.tap(btn);
      await tester.pumpAndSettle();

      // Should be back at Root (which is Home essentially in our route popUntil strategy)
      expect(find.text('Root'), findsOneWidget);
    });
  });
}
