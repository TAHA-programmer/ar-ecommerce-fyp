import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
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
import 'package:twin_ar/features/notifications/services/device_registration_service.dart';
import 'package:twin_ar/features/notifications/services/device_registration_store.dart';
import 'package:twin_ar/features/notifications/services/mock_device_registration_backend.dart';
import 'package:twin_ar/features/notifications/services/mock_fcm_message_source.dart';
import 'package:twin_ar/features/notifications/services/mock_fcm_token_source.dart';
import 'package:twin_ar/features/notifications/services/mock_notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_lifecycle.dart';
import 'package:twin_ar/features/notifications/services/notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_navigator.dart';
import 'package:twin_ar/features/notifications/services/notification_route_tracker.dart';
import 'package:twin_ar/features/notifications/services/notification_router.dart';
import 'package:twin_ar/features/notifications/widgets/notification_host.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/views/profile_view.dart';
import 'package:twin_ar/features/profile/widgets/profile_menu_item.dart';

/// Records, at the instant `signOut()` runs, how many device unregisters had
/// already happened - proving the unregister happens BEFORE sign-out.
class _RecordingAuthRepository extends MockAuthRepository {
  _RecordingAuthRepository(this._unregisterCalls);

  final List<String> _unregisterCalls;
  int? unregistersSeenAtSignOut;

  @override
  Future<void> signOut() async {
    unregistersSeenAtSignOut = _unregisterCalls.length;
    await super.signOut();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthSessionState auth;
  late MockDeviceRegistrationBackend backend;
  late MockFcmTokenSource tokens;
  late MockFcmMessageSource messages;
  late MockNotificationPermissionService permission;
  late DeviceRegistrationService registration;
  late NotificationLifecycle lifecycle;
  late _RecordingAuthRepository authRepo;
  late List<bool> optIns;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    auth = AuthSessionState();
    backend = MockDeviceRegistrationBackend();
    tokens = MockFcmTokenSource(token: 'token-A');
    messages = MockFcmMessageSource();
    permission = MockNotificationPermissionService();
    final store = DeviceRegistrationStore();
    registration = DeviceRegistrationService(
      tokens: tokens,
      backend: backend,
      permission: permission,
      store: store,
    );
    optIns = [];
    lifecycle = NotificationLifecycle(
      auth: auth,
      registration: registration,
      permission: permission,
      messages: messages,
      navigator: NotificationNavigator(
        navigatorKey: GlobalKey<NavigatorState>(),
        tracker: NotificationRouteTracker(),
        session: () => NotificationSession(
          uid: auth.userId,
          isCustomer: auth.isCustomer,
          isSuperAdmin: auth.isSuperAdmin,
        ),
      ),
      store: store,
      presentOptIn: ({required bool admin}) async {
        optIns.add(admin);
        return false;
      },
      presentBanner: ({required title, required body, required onTap}) {},
    );
    authRepo = _RecordingAuthRepository(backend.unregisterCalls);
  });

  tearDown(() async {
    await lifecycle.dispose();
    await messages.dispose();
    await tokens.dispose();
  });

  Widget app(Widget child, {bool withLifecycle = true}) {
    return MultiProvider(
      providers: [
        Provider<AuthRepository>.value(value: authRepo),
        ChangeNotifierProvider<AuthSessionState>.value(value: auth),
        ChangeNotifierProvider<CustomerProfileState>(
          create: (_) => CustomerProfileState(MockUserProfileRepository()),
        ),
        ChangeNotifierProvider<CustomerShoppingState>(
          create: (_) => CustomerShoppingState(
            MockFavoritesRepository(),
            MockCartRepository(),
          ),
        ),
        if (withLifecycle)
          Provider<NotificationLifecycle>.value(value: lifecycle),
      ],
      child: MaterialApp(
        home: child,
        routes: {
          RouteNames.login: (_) => const Scaffold(body: Text('Login Screen')),
          RouteNames.notificationSettings: (_) =>
              const Scaffold(body: Text('Settings Screen')),
          RouteNames.notifications: (_) =>
              const Scaffold(body: Text('Notifications Screen')),
        },
      ),
    );
  }

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  group('logout unregisters the device BEFORE signing out', () {
    testWidgets('customer (Profile)', (tester) async {
      bigView(tester);
      auth.setSession(
        AuthResult.success(
          userId: 'alice',
          email: 'a@x.com',
          role: UserRole.customer,
        ),
      );
      await lifecycle.start();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );

      await tester.pumpWidget(app(const ProfileView()));
      tester
          .widget<ProfileMenuItem>(
            find.widgetWithText(ProfileMenuItem, 'Log Out'),
          )
          .onTap();
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();

      expect(backend.unregisterCalls, ['token-A']);
      expect(tokens.deleteCount, 1);
      expect(
        authRepo.unregistersSeenAtSignOut,
        1,
        reason: 'unregister must already have happened when signOut ran',
      );
      expect(auth.isAuthenticated, isFalse);
      expect(find.text('Login Screen'), findsOneWidget);
    });

    testWidgets('admin (account sheet)', (tester) async {
      bigView(tester);
      auth.setSession(
        AuthResult.success(
          userId: 'admin-uid',
          email: 'a@x.com',
          role: UserRole.superAdmin,
        ),
      );
      await lifecycle.start();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );

      await tester.pumpWidget(app(const Scaffold(body: AdminAccountSheet())));
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
      await tester.pumpAndSettle();

      expect(backend.unregisterCalls, ['token-A']);
      expect(authRepo.unregistersSeenAtSignOut, 1);
      expect(find.text('Login Screen'), findsOneWidget);
    });

    testWidgets('a failing unregister never blocks the logout', (tester) async {
      bigView(tester);
      backend.unregisterResult = false;
      auth.setSession(
        AuthResult.success(
          userId: 'admin-uid',
          email: 'a@x.com',
          role: UserRole.superAdmin,
        ),
      );
      await lifecycle.start();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );

      await tester.pumpWidget(app(const Scaffold(body: AdminAccountSheet())));
      await tester.tap(find.text('Log Out'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
      await tester.pumpAndSettle();

      expect(auth.isAuthenticated, isFalse);
      expect(find.text('Login Screen'), findsOneWidget);
    });

    testWidgets(
      'a tree WITHOUT the lifecycle (tests, notifications disabled) still logs out normally',
      (tester) async {
        bigView(tester);
        auth.setSession(
          AuthResult.success(
            userId: 'admin-uid',
            email: 'a@x.com',
            role: UserRole.superAdmin,
          ),
        );
        await tester.pumpWidget(
          app(const Scaffold(body: AdminAccountSheet()), withLifecycle: false),
        );
        await tester.tap(find.text('Log Out'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
        await tester.pumpAndSettle();
        expect(auth.isAuthenticated, isFalse);
        expect(backend.unregisterCalls, isEmpty);
        expect(find.text('Login Screen'), findsOneWidget);
      },
    );

    testWidgets(
      'a lifecycle that was never started does not touch FCM on logout',
      (tester) async {
        bigView(tester);
        auth.setSession(
          AuthResult.success(
            userId: 'alice',
            email: 'a@x.com',
            role: UserRole.customer,
          ),
        );
        await tester.pumpWidget(app(const ProfileView()));
        tester
            .widget<ProfileMenuItem>(
              find.widgetWithText(ProfileMenuItem, 'Log Out'),
            )
            .onTap();
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(ElevatedButton, 'Logout'));
        await tester.pump(const Duration(seconds: 1));
        await tester.pumpAndSettle();
        expect(tokens.deleteCount, 0);
        expect(find.text('Login Screen'), findsOneWidget);
      },
    );
  });

  group('entry points', () {
    testWidgets(
      'Profile has a Notifications item (above My Orders) that opens the centre',
      (tester) async {
        bigView(tester);
        auth.setSession(
          AuthResult.success(
            userId: 'alice',
            email: 'a@x.com',
            role: UserRole.customer,
          ),
        );
        await tester.pumpWidget(app(const ProfileView()));
        await tester.pump();

        final notificationsItem = find.byKey(
          const Key('profile_notifications_item'),
        );
        expect(notificationsItem, findsOneWidget);
        final notifTop = tester.getTopLeft(notificationsItem).dy;
        final ordersTop = tester
            .getTopLeft(find.widgetWithText(ProfileMenuItem, 'My Orders'))
            .dy;
        expect(notifTop, lessThan(ordersTop));

        tester.widget<ProfileMenuItem>(notificationsItem).onTap();
        await tester.pumpAndSettle();
        expect(find.text('Notifications Screen'), findsOneWidget);
      },
    );

    testWidgets(
      'Admin account sheet has a Notification settings row that opens settings',
      (tester) async {
        bigView(tester);
        auth.setSession(
          AuthResult.success(
            userId: 'admin-uid',
            email: 'a@x.com',
            role: UserRole.superAdmin,
          ),
        );
        await tester.pumpWidget(app(const Scaffold(body: AdminAccountSheet())));
        await tester.tap(
          find.byKey(
            const Key('admin_account_sheet_notification_settings_tile'),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Settings Screen'), findsOneWidget);
      },
    );
  });

  group('NotificationOptInTrigger', () {
    testWidgets(
      'offers the opt-in once for a customer when permission is not granted',
      (tester) async {
        permission.current = NotificationPermissionStatus.denied;
        auth.setSession(
          AuthResult.success(
            userId: 'alice',
            email: 'a@x.com',
            role: UserRole.customer,
          ),
        );
        await tester.runAsync(() => lifecycle.start());

        await tester.pumpWidget(
          app(const Scaffold(body: NotificationOptInTrigger())),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();

        expect(optIns, [false]); // customer audience
      },
    );

    testWidgets('shows nothing when notifications are already allowed', (
      tester,
    ) async {
      auth.setSession(
        AuthResult.success(
          userId: 'alice',
          email: 'a@x.com',
          role: UserRole.customer,
        ),
      );
      await tester.runAsync(() => lifecycle.start());
      await tester.pumpWidget(
        app(const Scaffold(body: NotificationOptInTrigger())),
      );
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump();
      expect(optIns, isEmpty);
    });

    testWidgets('does nothing when the lifecycle is absent or not started', (
      tester,
    ) async {
      permission.current = NotificationPermissionStatus.denied;
      await tester.pumpWidget(
        app(
          const Scaffold(body: NotificationOptInTrigger()),
          withLifecycle: false,
        ),
      );
      await tester.pump();
      await tester.pump();
      expect(optIns, isEmpty);

      await tester.pumpWidget(const SizedBox());
      await tester.pumpWidget(
        app(const Scaffold(body: NotificationOptInTrigger())),
      );
      await tester.pump();
      await tester.pump();
      expect(optIns, isEmpty); // present but never started
    });
  });
}
