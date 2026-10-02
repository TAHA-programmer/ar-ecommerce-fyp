import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/notifications/services/device_registration_service.dart';
import 'package:twin_ar/features/notifications/services/device_registration_store.dart';
import 'package:twin_ar/features/notifications/services/fcm_message_source.dart';
import 'package:twin_ar/features/notifications/services/mock_device_registration_backend.dart';
import 'package:twin_ar/features/notifications/services/mock_fcm_message_source.dart';
import 'package:twin_ar/features/notifications/services/mock_fcm_token_source.dart';
import 'package:twin_ar/features/notifications/services/mock_notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_lifecycle.dart';
import 'package:twin_ar/features/notifications/services/notification_navigator.dart';
import 'package:twin_ar/features/notifications/services/notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_route_tracker.dart';
import 'package:twin_ar/features/notifications/services/notification_router.dart';

AuthResult _customer(String uid) => AuthResult.success(
  userId: uid,
  email: '$uid@x.com',
  role: UserRole.customer,
);
AuthResult _admin() => AuthResult.success(
  userId: 'admin-uid',
  email: 'a@x.com',
  role: UserRole.superAdmin,
);

IncomingPushMessage _msg(
  Map<String, dynamic> data, {
  String? title = 'Order shipped',
  String? body = 'On its way',
}) => IncomingPushMessage(data: data, title: title, body: body);

Map<String, dynamic> _shipped({
  String uid = 'alice',
  String order = 'ord_1',
  String? nid = 'order_shipped_ord_1',
}) => {
  'v': '1',
  'type': 'order_shipped',
  'audience': 'customer',
  'recipientUid': uid,
  'orderId': order,
  'notificationId': ?nid,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AuthSessionState auth;
  late MockFcmTokenSource tokens;
  late MockDeviceRegistrationBackend backend;
  late MockNotificationPermissionService permission;
  late MockFcmMessageSource messages;
  late DeviceRegistrationStore store;
  late DeviceRegistrationService registration;
  late NotificationRouteTracker tracker;
  late GlobalKey<NavigatorState> navKey;
  late NotificationNavigator navigator;
  late NotificationLifecycle lifecycle;

  late bool optInAnswer;
  late List<bool> optInAudiences;
  late List<({String title, String body})> banners;
  late List<VoidCallback> bannerTaps;
  late List<String> openedIds;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    auth = AuthSessionState();
    tokens = MockFcmTokenSource(token: 'token-A');
    backend = MockDeviceRegistrationBackend();
    permission = MockNotificationPermissionService(
      current: NotificationPermissionStatus.granted,
    );
    messages = MockFcmMessageSource();
    store = DeviceRegistrationStore();
    registration = DeviceRegistrationService(
      tokens: tokens,
      backend: backend,
      permission: permission,
      store: store,
    );
    tracker = NotificationRouteTracker();
    navKey = GlobalKey<NavigatorState>();
    navigator = NotificationNavigator(
      navigatorKey: navKey,
      tracker: tracker,
      session: () => NotificationSession(
        uid: auth.isAuthenticated ? auth.userId : null,
        isCustomer: auth.isCustomer,
        isSuperAdmin: auth.isSuperAdmin,
      ),
    );
    optInAnswer = true;
    optInAudiences = [];
    banners = [];
    bannerTaps = [];
    openedIds = [];
    lifecycle = NotificationLifecycle(
      auth: auth,
      registration: registration,
      permission: permission,
      messages: messages,
      navigator: navigator,
      store: store,
      presentOptIn: ({required bool admin}) async {
        optInAudiences.add(admin);
        return optInAnswer;
      },
      presentBanner: ({required title, required body, required onTap}) {
        banners.add((title: title, body: body));
        bannerTaps.add(onTap);
      },
      onNotificationOpened: openedIds.add,
    );
  });

  tearDown(() async {
    await lifecycle.dispose();
    await messages.dispose();
    await tokens.dispose();
  });

  Future<void> settle() =>
      Future<void>.delayed(const Duration(milliseconds: 20));

  group('start / auth attachment', () {
    test(
      'start is idempotent and registers the device when a user is already signed in',
      () async {
        auth.setSession(_customer('alice'));
        await lifecycle.start();
        await lifecycle.start();
        await settle();
        expect(lifecycle.isStarted, isTrue);
        expect(backend.registerCalls, hasLength(1));
        expect(backend.registerCalls.single.token, 'token-A');
      },
    );

    test(
      'a login after start registers; a re-notify for the same user does not repeat',
      () async {
        await lifecycle.start();
        await settle();
        expect(backend.registerCalls, isEmpty);

        auth.setSession(_customer('alice'));
        await settle();
        auth.setSession(_customer('alice'));
        await settle();
        expect(backend.registerCalls, hasLength(1));
      },
    );

    test(
      'never prompts for permission on login (D14) - no OS permission is requested',
      () async {
        permission.current = NotificationPermissionStatus.denied;
        await lifecycle.start();
        auth.setSession(_customer('alice'));
        await settle();
        expect(permission.requestCount, 0);
        expect(optInAudiences, isEmpty);
        expect(
          backend.registerCalls,
          isEmpty,
        ); // no permission => no registration
      },
    );

    test('switching users re-registers for the new user', () async {
      await lifecycle.start();
      auth.setSession(_customer('alice'));
      await settle();
      auth.clearSession();
      await settle();
      auth.setSession(_customer('bob'));
      await settle();
      expect((await store.lastRegistered())?.uid, 'bob');
    });

    test(
      'a rotated FCM token is re-registered for the signed-in user',
      () async {
        await lifecycle.start();
        auth.setSession(_customer('alice'));
        await settle();
        tokens.emitRefresh('token-B');
        await settle();
        expect(backend.registerCalls.map((c) => c.token), contains('token-B'));
      },
    );

    test('a cold-start (initial) message is handled once started', () async {
      messages.initial = _msg(_shipped());
      auth.setSession(_customer('alice'));
      await lifecycle.start();
      await settle();
      expect(openedIds, ['order_shipped_ord_1']);
    });
  });

  group('tap handling', () {
    test(
      'a valid tap marks the matching inbox row read (via callback)',
      () async {
        auth.setSession(_customer('alice'));
        await lifecycle.start();
        messages.emitOpened(_msg(_shipped()));
        await settle();
        expect(openedIds, ['order_shipped_ord_1']);
      },
    );

    test(
      'invalid payloads are ignored entirely (no pending tap, no read-mark)',
      () async {
        auth.setSession(_customer('alice'));
        await lifecycle.start();
        for (final bad in <Map<String, dynamic>>[
          {},
          {'v': '9', 'type': 'order_shipped'},
          {..._shipped(), 'type': 'teleport'},
          {..._shipped(), 'orderId': 'a/b'},
          {..._shipped()}..remove('recipientUid'),
        ]) {
          messages.emitOpened(_msg(bad));
        }
        await settle();
        expect(openedIds, isEmpty);
        expect(navigator.hasPending, isFalse);
      },
    );
  });

  group('foreground banner', () {
    test(
      'shows a banner for a valid push for this user, and tapping it opens the destination',
      () async {
        auth.setSession(_customer('alice'));
        await lifecycle.start();
        messages.emitForeground(_msg(_shipped()));
        await settle();
        expect(banners, hasLength(1));
        expect(banners.single.title, 'Order shipped');

        bannerTaps.single();
        await settle();
        expect(openedIds, ['order_shipped_ord_1']);
      },
    );

    test(
      'no banner for another account, a signed-out user, or an admin type on a customer',
      () async {
        await lifecycle.start();
        messages.emitForeground(_msg(_shipped())); // signed out
        auth.setSession(_customer('bob'));
        await settle();
        messages.emitForeground(_msg(_shipped(uid: 'alice'))); // not bob's
        messages.emitForeground(
          _msg({
            'v': '1',
            'type': 'admin_new_order',
            'audience': 'admin',
            'orderId': 'ord_1',
          }),
        );
        await settle();
        expect(banners, isEmpty);
      },
    );

    test('no banner for an invalid payload or one without a title', () async {
      auth.setSession(_customer('alice'));
      await lifecycle.start();
      messages.emitForeground(_msg({'v': '1'}));
      messages.emitForeground(_msg(_shipped(), title: null));
      messages.emitForeground(_msg(_shipped(), title: ''));
      await settle();
      expect(banners, isEmpty);
    });

    test('no banner when the user is ALREADY on that order', () async {
      auth.setSession(_customer('alice'));
      await lifecycle.start();
      // simulate being on Order Detail for ord_1
      final route = MaterialPageRoute<void>(
        settings: const RouteSettings(
          name: RouteNames.orderDetail,
          arguments: 'ord_1',
        ),
        builder: (_) => const SizedBox(),
      );
      tracker.didPush(route, null);
      messages.emitForeground(_msg(_shipped(order: 'ord_1')));
      await settle();
      expect(banners, isEmpty);
      messages.emitForeground(_msg(_shipped(order: 'ord_2')));
      await settle();
      expect(banners, hasLength(1));
    });

    test('an admin push banners for the superAdmin', () async {
      auth.setSession(_admin());
      await lifecycle.start();
      messages.emitForeground(
        _msg(
          {
            'v': '1',
            'type': 'admin_low_stock',
            'audience': 'admin',
            'productId': 'p1',
          },
          title: 'Low stock',
          body: 'Chair: 3 left.',
        ),
      );
      await settle();
      expect(banners.single.title, 'Low stock');
    });
  });

  group('beforeSignOut', () {
    test(
      'unregisters the device (server + local token) when started',
      () async {
        auth.setSession(_customer('alice'));
        await lifecycle.start();
        await settle();
        await lifecycle.beforeSignOut();
        expect(backend.unregisterCalls, ['token-A']);
        expect(tokens.deleteCount, 1);
        expect(await store.lastRegistered(), isNull);
      },
    );

    test(
      'is a no-op when the lifecycle was never started (tests / disabled)',
      () async {
        auth.setSession(_customer('alice'));
        await registration.sync('alice');
        await lifecycle.beforeSignOut();
        expect(backend.unregisterCalls, isEmpty);
        expect(tokens.deleteCount, 0);
      },
    );
  });

  group('contextual opt-in (D14)', () {
    test(
      'after an order: shows the sheet, "Turn on" requests permission and registers',
      () async {
        permission.current = NotificationPermissionStatus.denied;
        permission.afterRequest = NotificationPermissionStatus.granted;
        auth.setSession(_customer('alice'));
        await lifecycle.maybePromptAfterOrder();
        expect(optInAudiences, [false]);
        expect(permission.requestCount, 1);
        expect(backend.registerCalls, hasLength(1));
        expect(await store.promptDeclined(), isFalse);
      },
    );

    test('"Not now" records the decline and never asks again', () async {
      permission.current = NotificationPermissionStatus.denied;
      optInAnswer = false;
      auth.setSession(_customer('alice'));
      await lifecycle.maybePromptAfterOrder();
      expect(permission.requestCount, 0);
      expect(await store.promptDeclined(), isTrue);

      optInAnswer = true;
      await lifecycle.maybePromptAfterOrder();
      expect(optInAudiences, [false]); // not shown a second time
    });

    test(
      'the system dialog denying also records the decline (no nagging)',
      () async {
        permission.current = NotificationPermissionStatus.denied;
        permission.afterRequest = NotificationPermissionStatus.blocked;
        auth.setSession(_customer('alice'));
        await lifecycle.maybePromptAfterOrder();
        expect(await store.promptDeclined(), isTrue);
        expect(backend.registerCalls, isEmpty);
        await lifecycle.maybePromptAfterOrder();
        expect(optInAudiences, hasLength(1));
      },
    );

    test(
      'already granted: no sheet, just makes sure the device is registered',
      () async {
        auth.setSession(_customer('alice'));
        await lifecycle.maybePromptAfterOrder();
        await settle();
        expect(optInAudiences, isEmpty);
        expect(backend.registerCalls, hasLength(1));
      },
    );

    test(
      'only customers get the after-order prompt; only admins get the admin explainer',
      () async {
        permission.current = NotificationPermissionStatus.denied;
        auth.setSession(_admin());
        await lifecycle.maybePromptAfterOrder();
        expect(optInAudiences, isEmpty);

        await lifecycle.maybePromptAdmin();
        expect(optInAudiences, [true]);

        auth.setSession(_customer('alice'));
        await lifecycle.maybePromptAdmin();
        expect(optInAudiences, [true]);
      },
    );

    test(
      'a customer decline does not suppress the Admin explainer (separate flags)',
      () async {
        permission.current = NotificationPermissionStatus.denied;
        optInAnswer = false;
        auth.setSession(_customer('alice'));
        await lifecycle.maybePromptAfterOrder();
        expect(await store.promptDeclined(), isTrue);
        expect(await store.promptDeclined(admin: true), isFalse);

        auth.setSession(_admin());
        await lifecycle.maybePromptAdmin();
        expect(optInAudiences, [false, true]);
      },
    );

    test('nothing is shown when signed out', () async {
      permission.current = NotificationPermissionStatus.denied;
      expect(await lifecycle.promptOptIn(admin: false), isNull);
      expect(optInAudiences, isEmpty);
    });

    test(
      'force re-prompts even after a decline (settings entry points)',
      () async {
        permission.current = NotificationPermissionStatus.denied;
        permission.afterRequest = NotificationPermissionStatus.granted;
        await store.setPromptDeclined(true);
        auth.setSession(_customer('alice'));
        await lifecycle.promptOptIn(admin: false, force: true);
        expect(optInAudiences, [false]);
        expect(
          await store.promptDeclined(),
          isFalse,
        ); // grant clears the decline
      },
    );
  });

  group('requestFromSettings', () {
    test(
      'denied: requests the OS dialog directly (no sheet) and registers on grant',
      () async {
        permission.current = NotificationPermissionStatus.denied;
        permission.afterRequest = NotificationPermissionStatus.granted;
        auth.setSession(_customer('alice'));
        final status = await lifecycle.requestFromSettings(admin: false);
        expect(status, NotificationPermissionStatus.granted);
        expect(optInAudiences, isEmpty);
        expect(backend.registerCalls, hasLength(1));
      },
    );

    test(
      'blocked: opens system settings instead of a dialog that cannot show',
      () async {
        permission.current = NotificationPermissionStatus.blocked;
        auth.setSession(_customer('alice'));
        final status = await lifecycle.requestFromSettings(admin: false);
        expect(status, NotificationPermissionStatus.blocked);
        expect(permission.openSettingsCount, 1);
        expect(permission.requestCount, 0);
      },
    );

    test('already granted: just ensures registration', () async {
      auth.setSession(_customer('alice'));
      final status = await lifecycle.requestFromSettings(admin: false);
      await settle();
      expect(status, NotificationPermissionStatus.granted);
      expect(backend.registerCalls, hasLength(1));
      expect(permission.requestCount, 0);
    });
  });
}
