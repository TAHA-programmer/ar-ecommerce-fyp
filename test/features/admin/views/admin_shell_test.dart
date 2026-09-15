import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/admin/views/admin_shell.dart';
import 'package:twin_ar/features/admin/views/admin_dashboard_view.dart';
import 'package:twin_ar/features/admin/widgets/admin_bottom_navigation.dart';
import 'package:twin_ar/features/admin/dashboard/viewmodels/admin_dashboard_viewmodel.dart';
import 'package:twin_ar/features/admin/notifications/viewmodels/admin_notifications_viewmodel.dart';
import 'package:twin_ar/features/admin/notifications/views/admin_notifications_view.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/app/routes/route_names.dart';

OrderModel _pendingOrder(String id) {
  final date = DateTime(2026, 1, 1);
  return OrderModel(
    id: id,
    userId: 'test-uid',
    paymentId: 'pay_$id',
    items: const [],
    orderDate: date,
    subtotal: 0,
    deliveryFee: 0,
    discount: 0,
    total: 0,
    paymentMethod: PaymentMethod.stripeCard,
    paymentStatus: PaymentStatus.pending,
    orderStatus: OrderStatus.pending,
    deliveryAddress: AddressModel(
      fullName: 'Test User',
      phoneNumber: '9999999999',
      addressLine1: '1 Test Street',
      city: 'Lahore',
      provinceOrState: 'Punjab',
      postalCode: '00000',
    ),
    estimatedDeliveryStart: date.add(const Duration(days: 7)),
    estimatedDeliveryEnd: date.add(const Duration(days: 14)),
  );
}

void main() {
  Widget createTestWidget({
    String initialRoute = RouteNames.adminDashboard,
    AuthSessionState? authState,
    MockCommerceDatabase? db,
  }) {
    return MultiProvider(
      providers: [
        Provider<AuthRepository>(create: (_) => MockAuthRepository()),
        ChangeNotifierProvider<AuthSessionState>(
          create: (_) => authState ?? AuthSessionState(),
        ),
        ChangeNotifierProvider<CommerceDatabase>(
          create: (_) => db ?? MockCommerceDatabase(),
        ),
        ChangeNotifierProxyProvider<CommerceDatabase, AdminDashboardViewModel>(
          create: (context) =>
              AdminDashboardViewModel(context.read<CommerceDatabase>()),
          update: (context, db, previous) =>
              previous ?? AdminDashboardViewModel(db),
        ),
      ],
      child: MaterialApp(
        initialRoute: initialRoute,
        routes: {
          RouteNames.adminDashboard: (context) => const AdminDashboardView(),
          RouteNames.adminProducts: (context) =>
              const Scaffold(body: Text('Products Route')),
          RouteNames.adminInventory: (context) =>
              const Scaffold(body: Text('Inventory Route')),
          RouteNames.adminOrders: (context) =>
              const Scaffold(body: Text('Orders Route')),
          RouteNames.adminReviews: (context) =>
              const Scaffold(body: Text('Reviews Route')),
          RouteNames.adminNotifications: (context) => ChangeNotifierProvider(
            create: (context) =>
                AdminNotificationsViewModel(context.read<CommerceDatabase>()),
            child: const AdminNotificationsView(),
          ),
        },
      ),
    );
  }

  testWidgets('AdminDashboardView renders AdminShell and BottomNavigation', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.byType(AdminShell), findsOneWidget);
    expect(find.byType(AdminBottomNavigation), findsOneWidget);

    // Check exactly 4 bottom nav items exist (by finding their icons/labels)
    expect(find.text('Dashboard'), findsOneWidget);
    expect(find.text('Products'), findsOneWidget);
    expect(find.text('Inventory'), findsOneWidget);
    expect(find.text('Orders'), findsOneWidget);

    // Ensure "Zara" is not hardcoded
    expect(find.text('Hello, Zara 👋'), findsNothing);
  });

  testWidgets('Bottom navigation taps trigger replacement routing', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    // Tap Products (index 1)
    await tester.tap(find.text('Products'));
    await tester.pumpAndSettle();

    expect(find.text('Products Route'), findsOneWidget);
    expect(find.byType(AdminDashboardView), findsNothing);
  });

  testWidgets('Notification bell opens the dedicated AdminNotificationsView', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    final bellIcon = find.byIcon(Icons.notifications_none);
    expect(bellIcon, findsOneWidget);

    await tester.tap(bellIcon);
    await tester.pumpAndSettle();

    expect(find.byType(AdminNotificationsView), findsOneWidget);
    expect(find.text('Notifications'), findsOneWidget);

    // Tap back to return to the Dashboard.
    await tester.tap(find.byKey(const Key('admin_notifications_back_button')));
    await tester.pumpAndSettle();
    expect(find.byType(AdminNotificationsView), findsNothing);
    expect(find.byType(AdminDashboardView), findsOneWidget);
  });

  testWidgets('Notification badge is hidden when there is nothing to flag', (
    WidgetTester tester,
  ) async {
    // The default MockCommerceDatabase fixture has no orders and every
    // product comfortably above the low-stock threshold.
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('admin_notification_badge')), findsNothing);
  });

  testWidgets(
    'Notification badge shows the real count once a product goes low in '
    'stock, and the Notifications screen lists it',
    (WidgetTester tester) async {
      final db = MockCommerceDatabase();
      final lowStockProduct = db.products.first;
      await db.updateStock(lowStockProduct.id, 2);

      await tester.pumpWidget(createTestWidget(db: db));
      await tester.pumpAndSettle();

      final badge = find.byKey(const Key('admin_notification_badge'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('1')),
        findsOneWidget,
      );

      await tester.tap(find.byIcon(Icons.notifications_none));
      await tester.pumpAndSettle();

      expect(find.textContaining('Low Stock Products'), findsOneWidget);
      expect(find.text(lowStockProduct.title), findsOneWidget);
    },
  );

  testWidgets(
    'Notification badge count sums low-stock products and pending orders, '
    'and grows past a single digit without truncation',
    (WidgetTester tester) async {
      final db = MockCommerceDatabase();
      // Push 11 products low in stock (past a single digit) plus 1 pending
      // order, so the expected count is a genuinely summed 12 - not a
      // hardcoded or capped value.
      for (final product in db.products.take(11)) {
        await db.updateStock(product.id, 2);
      }
      db.addOrder(_pendingOrder('order-badge-test'));

      await tester.pumpWidget(createTestWidget(db: db));
      await tester.pumpAndSettle();

      final badge = find.byKey(const Key('admin_notification_badge'));
      expect(badge, findsOneWidget);
      expect(
        find.descendant(of: badge, matching: find.text('12')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'Profile icon opens AdminAccountSheet reading from AuthSessionState',
    (WidgetTester tester) async {
      final authState = AuthSessionState();
      // Use reflection-like or direct if fields are public. In this mock, we just use the default fallback if no setter.
      // We'll rely on the default admin@twinar.com since we can't easily set it without login context, or we can mock it.

      await tester.pumpWidget(createTestWidget(authState: authState));
      await tester.pumpAndSettle();

      final profileIcon = find.byIcon(Icons.person);
      expect(profileIcon, findsOneWidget);

      await tester.tap(profileIcon);
      await tester.pumpAndSettle();

      expect(find.text('Super Admin'), findsWidgets);
      expect(find.text('admin@twinar.com'), findsOneWidget);
      expect(find.text('Log Out'), findsOneWidget);
    },
  );

  testWidgets('AdminAccountSheet\'s "Reviews Moderation" tile navigates to '
      'RouteNames.adminReviews', (WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.person));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('admin_account_sheet_reviews_tile')));
    await tester.pumpAndSettle();

    expect(find.text('Reviews Route'), findsOneWidget);
  });
}
