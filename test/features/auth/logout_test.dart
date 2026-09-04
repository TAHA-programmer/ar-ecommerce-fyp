import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/admin/widgets/admin_account_sheet.dart';
import 'package:twin_ar/features/profile/views/profile_view.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/profile/widgets/profile_menu_item.dart';

void main() {
  Widget createTestWidget({
    required Widget child,
    required AuthSessionState authState,
    required AuthRepository authRepo,
  }) {
    return MultiProvider(
      providers: [
        Provider<AuthRepository>.value(value: authRepo),
        ChangeNotifierProvider<AuthSessionState>.value(value: authState),
        ChangeNotifierProvider<CustomerProfileState>(
          create: (_) => CustomerProfileState(MockUserProfileRepository()),
        ),
        ChangeNotifierProvider<CustomerShoppingState>(
          create: (_) => CustomerShoppingState(
            MockFavoritesRepository(),
            MockCartRepository(),
          ),
        ),
      ],
      child: MaterialApp(
        home: child,
        routes: {
          RouteNames.login: (context) =>
              const Scaffold(body: Text('Login Screen')),
        },
      ),
    );
  }

  testWidgets('Admin logout clears AuthSessionState and routes to Login', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authState = AuthSessionState();
    authState.setSession(
      AuthResult.success(
        userId: '1',
        email: 'admin@twinar.com',
        role: UserRole.superAdmin,
      ),
    );
    final authRepo = MockAuthRepository();

    await tester.pumpWidget(
      createTestWidget(
        child: const Scaffold(body: AdminAccountSheet()),
        authState: authState,
        authRepo: authRepo,
      ),
    );

    // Initial state
    expect(authState.isAuthenticated, isTrue);
    expect(authState.isSuperAdmin, isTrue);

    // Tap the Log Out button
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();

    // Verify session cleared
    expect(authState.isAuthenticated, isFalse);
    expect(authState.userId, isNull);

    // Verify navigated to login
    expect(find.text('Login Screen'), findsOneWidget);
    expect(find.byType(AdminAccountSheet), findsNothing);
  });

  testWidgets('Customer logout clears AuthSessionState and routes to Login', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authState = AuthSessionState();
    authState.setSession(
      AuthResult.success(
        userId: '2',
        email: 'customer@twinar.com',
        role: UserRole.customer,
      ),
    );
    final authRepo = MockAuthRepository();

    await tester.pumpWidget(
      createTestWidget(
        child: const ProfileView(),
        authState: authState,
        authRepo: authRepo,
      ),
    );

    // Initial state
    expect(authState.isAuthenticated, isTrue);
    expect(authState.isCustomer, isTrue);

    // Find the Log Out list tile and call onTap directly to bypass layout/scroll issues in tests
    final logOutTile = tester.widget<ProfileMenuItem>(
      find.widgetWithText(ProfileMenuItem, 'Log Out'),
    );
    logOutTile.onTap();
    await tester.pumpAndSettle();

    // A confirmation dialog appears; signing out has NOT happened yet.
    expect(find.text('Log Out?'), findsOneWidget);
    expect(find.text('Are you sure you want to log out?'), findsOneWidget);
    expect(authState.isAuthenticated, isTrue);

    // Confirm via the dialog's "Logout" button.
    await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
    await tester.pump(const Duration(seconds: 1));
    await tester.pumpAndSettle();

    // Verify session cleared
    expect(authState.isAuthenticated, isFalse);
    expect(authState.userId, isNull);

    // Verify navigated to login
    expect(find.text('Login Screen'), findsOneWidget);
    expect(find.byType(ProfileView), findsNothing);
  });

  testWidgets('Customer logout confirmation - Cancel does not sign out', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final authState = AuthSessionState();
    authState.setSession(
      AuthResult.success(
        userId: '2',
        email: 'customer@twinar.com',
        role: UserRole.customer,
      ),
    );
    final authRepo = MockAuthRepository();

    await tester.pumpWidget(
      createTestWidget(
        child: const ProfileView(),
        authState: authState,
        authRepo: authRepo,
      ),
    );

    final logOutTile = tester.widget<ProfileMenuItem>(
      find.widgetWithText(ProfileMenuItem, 'Log Out'),
    );
    logOutTile.onTap();
    await tester.pumpAndSettle();

    expect(find.text('Log Out?'), findsOneWidget);

    // Tap Cancel instead of Logout.
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    // Dialog dismissed, session untouched, still on Profile.
    expect(find.text('Log Out?'), findsNothing);
    expect(authState.isAuthenticated, isTrue);
    expect(authState.isCustomer, isTrue);
    expect(find.byType(ProfileView), findsOneWidget);
    expect(find.text('Login Screen'), findsNothing);
  });
}
