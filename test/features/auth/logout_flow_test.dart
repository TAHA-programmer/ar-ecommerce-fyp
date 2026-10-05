import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/admin/widgets/admin_account_sheet.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/features/auth/widgets/logout_flow.dart';
import 'package:twin_ar/features/notifications/services/notification_lifecycle.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/views/profile_view.dart';
import 'package:twin_ar/features/profile/widgets/profile_menu_item.dart';

/// signOut() stays pending until [release] is called (or throws when
/// [failWith] is set), and every call is recorded.
class _GatedAuthRepository extends MockAuthRepository {
  _GatedAuthRepository(this.events);

  final List<String> events;
  // Created lazily INSIDE the test zone: a Completer built in setUp lives in
  // the real zone and its continuation would never run under FakeAsync.
  Completer<void>? _gate;
  Object? failWith;
  int signOutCalls = 0;

  void release() => _gate!.complete();

  @override
  Future<void> signOut() async {
    signOutCalls++;
    events.add('signOut');
    if (failWith != null) throw failWith!;
    await (_gate = Completer<void>()).future;
  }
}

class _FakeLifecycle implements NotificationLifecycle {
  _FakeLifecycle(this.events);
  final List<String> events;

  @override
  Future<void> beforeSignOut() async => events.add('beforeSignOut');

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late List<String> events;
  late AuthSessionState authState;
  late _GatedAuthRepository repo;

  setUp(() {
    LogoutFlow.resetForTest();
    events = [];
    repo = _GatedAuthRepository(events);
    authState = AuthSessionState();
  });

  Widget harness(Widget child) {
    return MultiProvider(
      providers: [
        Provider<AuthRepository>.value(value: repo),
        Provider<NotificationLifecycle?>.value(value: _FakeLifecycle(events)),
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
          RouteNames.login: (_) => const Scaffold(body: Text('Login Screen')),
        },
      ),
    );
  }

  void signIn(UserRole role) => authState.setSession(
    AuthResult.success(userId: 'u1', email: 'a@b.com', role: role),
  );

  void bigScreen(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<void> confirmLogout(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
  }

  void tapCustomerLogoutTile(WidgetTester tester) {
    tester
        .widget<ProfileMenuItem>(
          find.widgetWithText(ProfileMenuItem, 'Log Out'),
        )
        .onTap();
  }

  testWidgets(
    'Admin: overlay blocks UI and re-entry while sign-out is pending',
    (tester) async {
      bigScreen(tester);
      signIn(UserRole.superAdmin);
      await tester.pumpWidget(
        harness(const Scaffold(body: AdminAccountSheet())),
      );

      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
      await confirmLogout(tester);

      // Pending: overlay shown, session NOT yet cleared, Login not yet shown.
      expect(find.text('Signing out…'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(LogoutFlow.isInFlight, isTrue);
      expect(authState.isAuthenticated, isTrue);
      expect(find.text('Login Screen'), findsNothing);

      // A tap on the barrier does not dismiss it, and a second run is ignored.
      await tester.tapAt(const Offset(5, 5));
      await tester.pump();
      expect(find.text('Signing out…'), findsOneWidget);
      final ctx = tester.element(find.byType(AdminAccountSheet));
      await LogoutFlow.run(ctx);
      expect(repo.signOutCalls, 1);

      repo.release();
      await tester.pumpAndSettle();

      expect(authState.isAuthenticated, isFalse);
      expect(find.text('Login Screen'), findsOneWidget);
      expect(find.text('Signing out…'), findsNothing);
      expect(LogoutFlow.isInFlight, isFalse);
      expect(repo.signOutCalls, 1);
    },
  );

  testWidgets(
    'Customer: overlay blocks UI and re-entry while sign-out is pending',
    (tester) async {
      bigScreen(tester);
      signIn(UserRole.customer);
      await tester.pumpWidget(harness(const ProfileView()));

      tapCustomerLogoutTile(tester);
      await tester.pumpAndSettle();
      await confirmLogout(tester);

      expect(find.text('Signing out…'), findsOneWidget);
      expect(authState.isAuthenticated, isTrue);

      // Re-triggering the tile while pending opens no second dialog.
      tapCustomerLogoutTile(tester);
      await tester.pump();
      expect(find.text('Log Out?'), findsNothing);
      expect(repo.signOutCalls, 1);

      repo.release();
      await tester.pumpAndSettle();
      expect(authState.isAuthenticated, isFalse);
      expect(find.text('Login Screen'), findsOneWidget);
      expect(find.text('Signing out…'), findsNothing);
    },
  );

  testWidgets(
    'keeps the secure order: FCM cleanup, signOut, then session clear',
    (tester) async {
      bigScreen(tester);
      signIn(UserRole.customer);
      await tester.pumpWidget(harness(const ProfileView()));

      tapCustomerLogoutTile(tester);
      await tester.pumpAndSettle();
      await confirmLogout(tester);

      expect(events, ['beforeSignOut', 'signOut']);
      expect(authState.isAuthenticated, isTrue); // not cleared before signOut
      repo.release();
      await tester.pumpAndSettle();
      expect(authState.isAuthenticated, isFalse);
    },
  );

  testWidgets('failure removes the overlay, keeps the session, allows retry', (
    tester,
  ) async {
    bigScreen(tester);
    signIn(UserRole.superAdmin);
    repo.failWith = StateError('boom');
    await tester.pumpWidget(harness(const Scaffold(body: AdminAccountSheet())));

    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    await confirmLogout(tester);
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('Signing out…'), findsNothing);
    expect(find.text('Could not log out. Please try again.'), findsOneWidget);
    expect(authState.isAuthenticated, isTrue);
    expect(find.text('Login Screen'), findsNothing);
    expect(LogoutFlow.isInFlight, isFalse);

    // Retry now works.
    repo.failWith = null;
    await tester.pump(const Duration(seconds: 5)); // let the toast go
    await tester.tap(find.text('Log Out'));
    await tester.pumpAndSettle();
    await confirmLogout(tester);
    repo.release();
    await tester.pumpAndSettle();
    expect(authState.isAuthenticated, isFalse);
    expect(find.text('Login Screen'), findsOneWidget);
  });
}
