import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/customer_order_state.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/orders/viewmodels/my_orders_viewmodel.dart';
import 'package:twin_ar/features/orders/views/my_orders_view.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';

void main() {
  group('MyOrdersView Tests', () {
    late MockCommerceDatabase db;
    late CustomerOrderState orderState;
    late MyOrdersViewModel viewModel;

    setUp(() {
      db = MockCommerceDatabase();
      orderState = CustomerOrderState(db);
      viewModel = MyOrdersViewModel(orderState: orderState);
    });

    Widget buildTestWidget() {
      return MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: orderState),
          ChangeNotifierProvider.value(value: viewModel),
        ],
        child: MaterialApp(
          home: const MyOrdersView(),
          routes: {
            '/order-detail': (context) {
              final args =
                  ModalRoute.of(context)?.settings.arguments as String?;
              return Scaffold(body: Text('Order Detail: $args'));
            },
          },
        ),
      );
    }

    testWidgets('Shows empty state when no orders exist', (tester) async {
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('No orders yet'), findsOneWidget);
      expect(find.text('Start Shopping'), findsOneWidget);
    });

    testWidgets('Shows orders and proper text based on filter', (tester) async {
      final order = OrderModel(
        id: 'TAR123',
        userId: 'test-uid',
        paymentId: 'pay_TAR123',
        items: [
          OrderItemModel(
            productId: 'p1',
            productName: 'Test Product',
            unitPrice: 100,
            lineTotal: 100,
            quantity: 1,
            imagePath: 'assets/images/placeholder.png',
          ),
        ],
        orderDate: DateTime(2025, 5, 16),
        subtotal: 100,
        deliveryFee: 10,
        discount: 0,
        total: 110,
        paymentMethod: PaymentMethod.stripeCard,
        paymentStatus: PaymentStatus.paid,
        orderStatus: OrderStatus.pending,
        deliveryAddress: AddressModel(
          id: 'A1',
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

      db.addOrder(order);
      await tester.pumpWidget(buildTestWidget());

      // Should show the order in 'All' filter
      expect(find.text('#TAR123'), findsOneWidget);
      expect(find.text('Stripe'), findsOneWidget);
      expect(find.text('Pending'), findsWidgets); // Status pill and filter pill

      // Tap on 'Confirmed' filter
      await tester.tap(find.text('Confirmed').first);
      await tester.pumpAndSettle();

      // Should show filter empty state
      expect(find.text('No Confirmed orders'), findsOneWidget);
      expect(find.text('#TAR123'), findsNothing);
    });
    testWidgets('Tapping View Details navigates to Order Detail route', (
      tester,
    ) async {
      final order = OrderModel(
        id: 'TAR123',
        userId: 'test-uid',
        paymentId: 'pay_TAR123',
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
      await tester.pumpWidget(buildTestWidget());

      expect(find.text('View Details'), findsOneWidget);
      await tester.tap(find.text('View Details'));
      await tester.pumpAndSettle();

      expect(find.text('Order Detail: TAR123'), findsOneWidget);
    });
  });
}
