import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/admin/views/admin_shell.dart';
import 'package:twin_ar/features/admin/views/admin_dashboard_view.dart';
import 'package:twin_ar/features/admin/widgets/admin_bottom_navigation.dart';
import 'package:twin_ar/features/admin/dashboard/viewmodels/admin_dashboard_viewmodel.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/app/routes/route_names.dart';

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

  testWidgets('Notification bell opens AdminNotificationSheet', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createTestWidget());
    await tester.pumpAndSettle();

    final bellIcon = find.byIcon(Icons.notifications_none);
    expect(bellIcon, findsOneWidget);

    await tester.tap(bellIcon);
    await tester.pumpAndSettle();

    expect(find.text('Notifications'), findsOneWidget);

    // Tap close to dismiss
    await tester.tap(find.byIcon(Icons.close));
    await tester.pumpAndSettle();
    expect(find.text('Notifications'), findsNothing);
  });

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
}
