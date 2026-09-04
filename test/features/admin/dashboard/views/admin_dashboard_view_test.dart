import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/admin/dashboard/viewmodels/admin_dashboard_viewmodel.dart';
import 'package:twin_ar/features/admin/dashboard/widgets/admin_recent_order_tile.dart';
import 'package:twin_ar/features/admin/views/admin_dashboard_view.dart';

OrderModel _buildOrder({required String id, DateTime? orderDate}) {
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
      fullName: 'Alice Walker',
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

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CommerceDatabase>.value(value: db),
        ChangeNotifierProvider<AuthSessionState>(
          create: (_) => AuthSessionState(),
        ),
        ChangeNotifierProvider<AdminDashboardViewModel>(
          create: (_) => AdminDashboardViewModel(db),
        ),
      ],
      child: MaterialApp(
        home: const AdminDashboardView(),
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

  group('AdminDashboardView - Recent Orders entry point', () {
    testWidgets(
      'tapping a Recent Order tile navigates to Admin Order Detail with the '
      'correct orderId',
      (tester) async {
        db.addOrder(_buildOrder(id: '#TW00000001'));

        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        final tile = find.byType(AdminRecentOrderTile);
        expect(tile, findsOneWidget);

        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();

        expect(
          find.text('Admin Order Detail Stub: #TW00000001'),
          findsOneWidget,
        );
      },
    );

    testWidgets('the Dashboard itself is otherwise unaffected', (tester) async {
      db.addOrder(_buildOrder(id: '#TW00000001'));

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Recent Orders'), findsOneWidget);
      expect(find.byType(AdminRecentOrderTile), findsOneWidget);
    });
  });
}
