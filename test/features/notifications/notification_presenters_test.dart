import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/app/routes/app_router.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/notifications/notification_presenters.dart';
import 'package:twin_ar/features/notifications/services/device_registration_service.dart';
import 'package:twin_ar/features/notifications/services/device_registration_store.dart';
import 'package:twin_ar/features/notifications/services/fcm_message_source.dart';
import 'package:twin_ar/features/notifications/services/mock_device_registration_backend.dart';
import 'package:twin_ar/features/notifications/services/mock_fcm_message_source.dart';
import 'package:twin_ar/features/notifications/services/mock_fcm_token_source.dart';
import 'package:twin_ar/features/notifications/services/mock_notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_lifecycle.dart';
import 'package:twin_ar/features/notifications/services/notification_navigator.dart';
import 'package:twin_ar/features/notifications/services/notification_route_tracker.dart';
import 'package:twin_ar/features/notifications/services/notification_router.dart';

/// S8 foreground-retest regression: the production banner/sheet presenters run
/// against the REAL root navigator key (`AppRouter.navigatorKey`), which the
/// mock-presenter tests of S5 never exercised. The banner threw "No Overlay
/// widget found" (it looked for an Overlay ABOVE the Overlay's own context),
/// inside the FCM stream listener, so nothing was ever shown.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final tracker = NotificationRouteTracker();
  late List<String> pushed;

  Future<void> pumpApp(WidgetTester tester) async {
    pushed = [];
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: AppRouter.navigatorKey,
        navigatorObservers: [tracker],
        initialRoute: RouteNames.home,
        onGenerateRoute: (settings) {
          if (settings.name != RouteNames.home) {
            pushed.add('${settings.name}|${settings.arguments}');
          }
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => Scaffold(body: Text('PAGE ${settings.name}')),
          );
        },
      ),
    );
    await tester.pump();
  }

  tearDown(() => tracker.debugReset());

  group('presentPushBanner (production presenter, real navigator key)', () {
    testWidgets('shows the banner with title + body without throwing', (
      tester,
    ) async {
      await pumpApp(tester);
      presentPushBanner(
        title: 'Order shipped',
        body: 'Order #AB12 is on its way.',
        onTap: () {},
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Order shipped'), findsOneWidget);
      expect(find.text('Order #AB12 is on its way.'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('Order shipped'), findsNothing);
    });

    testWidgets('tapping the banner calls onTap once and dismisses it', (
      tester,
    ) async {
      await pumpApp(tester);
      var taps = 0;
      presentPushBanner(title: 'T', body: 'B', onTap: () => taps++);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.tap(find.text('T'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(taps, 1);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.text('T'), findsNothing);
    });

    testWidgets('a second banner replaces the first', (tester) async {
      await pumpApp(tester);
      presentPushBanner(title: 'First', body: 'a', onTap: () {});
      await tester.pump(const Duration(milliseconds: 400));
      presentPushBanner(title: 'Second', body: 'b', onTap: () {});
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Second'), findsOneWidget);
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
    });

    testWidgets('without a mounted navigator it does nothing (no throw)', (
      tester,
    ) async {
      await tester.pumpWidget(const SizedBox());
      expect(
        () => presentPushBanner(title: 'T', body: 'B', onTap: () {}),
        returnsNormally,
      );
    });
  });

  group('presentOptInSheet (production presenter, real navigator key)', () {
    testWidgets('shows the sheet and resolves the user choice', (tester) async {
      await pumpApp(tester);
      Future<bool?>? result;
      result = presentOptInSheet(admin: false);
      await tester.pumpAndSettle();
      expect(find.text('Get order updates'), findsOneWidget);
      await tester.tap(
        find.byKey(const Key('notification_permission_turn_on')),
      );
      await tester.pumpAndSettle();
      expect(await result, isTrue);
    });
  });

  group('foreground push -> banner, end to end with the real presenters', () {
    late AuthSessionState auth;
    late MockFcmMessageSource messages;
    late MockFcmTokenSource tokens;
    late DeviceRegistrationService registration;
    late NotificationLifecycle lifecycle;

    IncomingPushMessage shipped({String order = 'ord_1'}) =>
        IncomingPushMessage(
          title: 'Order shipped',
          body: 'Order #AB12 is on its way.',
          data: {
            'v': '1',
            'type': 'order_shipped',
            'audience': 'customer',
            'recipientUid': 'alice',
            'orderId': order,
            'notificationId': 'order_shipped_$order',
          },
        );

    NotificationLifecycle build({BannerPresenter? banner}) {
      final store = DeviceRegistrationStore();
      return NotificationLifecycle(
        auth: auth,
        registration: registration,
        permission: MockNotificationPermissionService(),
        messages: messages,
        navigator: NotificationNavigator(
          navigatorKey: AppRouter.navigatorKey,
          tracker: tracker,
          session: () => NotificationSession(
            uid: auth.isAuthenticated ? auth.userId : null,
            isCustomer: auth.isCustomer,
            isSuperAdmin: auth.isSuperAdmin,
          ),
        ),
        store: store,
        presentOptIn: presentOptInSheet,
        presentBanner: banner ?? presentPushBanner,
      );
    }

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      auth = AuthSessionState()
        ..setSession(
          AuthResult.success(
            userId: 'alice',
            email: 'a@x.com',
            role: UserRole.customer,
          ),
        );
      messages = MockFcmMessageSource();
      tokens = MockFcmTokenSource(token: 'token-A');
      registration = DeviceRegistrationService(
        tokens: tokens,
        backend: MockDeviceRegistrationBackend(),
        permission: MockNotificationPermissionService(),
      );
      lifecycle = build();
    });

    tearDown(() async {
      await lifecycle.dispose();
      await messages.dispose();
      await tokens.dispose();
    });

    testWidgets(
      'a foreground message on Home shows the banner; tapping opens the order',
      (tester) async {
        await pumpApp(tester);
        await tester.runAsync(() => lifecycle.start());

        messages.emitForeground(shipped());
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));

        expect(find.text('Order shipped'), findsOneWidget);
        expect(find.text('Order #AB12 is on its way.'), findsOneWidget);

        await tester.tap(find.text('Order shipped'));
        await tester.pumpAndSettle();
        // (initialRoute '/home' also builds '/' first - only the last push matters)
        expect(pushed.last, '${RouteNames.orderDetail}|ord_1');
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'no banner when already on that order; no banner for another account',
      (tester) async {
        await pumpApp(tester);
        await tester.runAsync(() => lifecycle.start());

        AppRouter.navigatorKey.currentState!.pushNamed(
          RouteNames.orderDetail,
          arguments: 'ord_1',
        );
        await tester.pumpAndSettle();
        pushed.clear();

        messages.emitForeground(shipped(order: 'ord_1'));
        messages.emitForeground(
          IncomingPushMessage(
            title: 'Other',
            body: 'x',
            data: {...shipped().data, 'recipientUid': 'bob'},
          ),
        );
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Order shipped'), findsNothing);
        expect(find.text('Other'), findsNothing);
      },
    );

    testWidgets(
      'a presenter that throws never breaks later foreground handling',
      (tester) async {
        await pumpApp(tester);
        await lifecycle.dispose();
        var calls = 0;
        lifecycle = build(
          banner: ({required title, required body, required onTap}) {
            calls++;
            if (calls == 1) throw StateError('ui exploded');
          },
        );
        await tester.runAsync(() => lifecycle.start());

        messages.emitForeground(shipped());
        messages.emitForeground(shipped(order: 'ord_2'));
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 30)),
        );
        expect(calls, 2); // the second message was still handled
        expect(tester.takeException(), isNull);
      },
    );
  });
}
