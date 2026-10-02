import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/features/notifications/notification_constants.dart';
import 'package:twin_ar/features/notifications/services/device_registration_service.dart';
import 'package:twin_ar/features/notifications/services/device_registration_store.dart';
import 'package:twin_ar/features/notifications/services/mock_device_registration_backend.dart';
import 'package:twin_ar/features/notifications/services/mock_fcm_token_source.dart';
import 'package:twin_ar/features/notifications/services/mock_notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_permission_service.dart';

void main() {
  late MockFcmTokenSource tokens;
  late MockDeviceRegistrationBackend backend;
  late MockNotificationPermissionService permission;
  late DeviceRegistrationStore store;
  late DateTime now;
  late DeviceRegistrationService service;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    tokens = MockFcmTokenSource(token: 'token-A');
    backend = MockDeviceRegistrationBackend();
    permission = MockNotificationPermissionService();
    store = DeviceRegistrationStore();
    now = DateTime.utc(2026, 10, 2, 12);
    service = DeviceRegistrationService(
      tokens: tokens,
      backend: backend,
      permission: permission,
      store: store,
      clock: () => now,
    );
  });

  tearDown(() async {
    await service.dispose();
    await tokens.dispose();
  });

  group('sync', () {
    test(
      'registers once with token, install id, app version - and no role',
      () async {
        final outcome = await service.sync('alice');

        expect(outcome, DeviceRegistrationOutcome.registered);
        expect(backend.registerCalls, hasLength(1));
        final call = backend.registerCalls.single;
        expect(call.token, 'token-A');
        expect(call.appVersion, NotificationConstants.appVersion);
        expect(call.installId, await store.installId());
        expect(call.installId, matches(RegExp(r'^[0-9a-f]{32}$')));
        final saved = await store.lastRegistered();
        expect(saved?.uid, 'alice');
        expect(saved?.token, 'token-A');
      },
    );

    test(
      'does nothing without OS permission (no token fetch, no call)',
      () async {
        for (final status in [
          NotificationPermissionStatus.denied,
          NotificationPermissionStatus.blocked,
        ]) {
          permission.current = status;
          expect(
            await service.sync('alice'),
            DeviceRegistrationOutcome.skippedNoPermission,
          );
        }
        expect(backend.registerCalls, isEmpty);
        expect(tokens.getCount, 0);
        expect(await store.lastRegistered(), isNull);
      },
    );

    test('reports noToken when FCM has none (null or empty)', () async {
      tokens.token = null;
      expect(await service.sync('alice'), DeviceRegistrationOutcome.noToken);
      tokens.token = '';
      expect(await service.sync('alice'), DeviceRegistrationOutcome.noToken);
      expect(backend.registerCalls, isEmpty);
    });

    test(
      'is a no-op when the same token/user was registered less than 7 days ago',
      () async {
        await service.sync('alice');
        now = now.add(const Duration(days: 6, hours: 23));
        expect(await service.sync('alice'), DeviceRegistrationOutcome.upToDate);
        expect(backend.registerCalls, hasLength(1));
      },
    );

    test(
      're-registers after 7 days, on force, on a new token and on a new user',
      () async {
        await service.sync('alice');

        now = now.add(const Duration(days: 7));
        expect(
          await service.sync('alice'),
          DeviceRegistrationOutcome.registered,
        );
        expect(backend.registerCalls, hasLength(2));

        expect(
          await service.sync('alice', force: true),
          DeviceRegistrationOutcome.registered,
        );
        expect(backend.registerCalls, hasLength(3));

        tokens.token = 'token-B';
        expect(
          await service.sync('alice'),
          DeviceRegistrationOutcome.registered,
        );
        expect(backend.registerCalls.last.token, 'token-B');

        expect(await service.sync('bob'), DeviceRegistrationOutcome.registered);
        expect(backend.registerCalls, hasLength(5));
        expect((await store.lastRegistered())?.uid, 'bob');
      },
    );

    test(
      'a failed callable is reported, not thrown, and not remembered (retried later)',
      () async {
        backend.registerResult = false;
        expect(await service.sync('alice'), DeviceRegistrationOutcome.failed);
        expect(await store.lastRegistered(), isNull);

        backend.registerResult = true;
        expect(
          await service.sync('alice'),
          DeviceRegistrationOutcome.registered,
        );
        expect(backend.registerCalls, hasLength(2));
      },
    );

    test('keeps the same install id across syncs', () async {
      await service.sync('alice', force: true);
      await service.sync('alice', force: true);
      final ids = backend.registerCalls.map((c) => c.installId).toSet();
      expect(ids, hasLength(1));
    });
  });

  group('token refresh', () {
    test('re-registers the NEW token for the current user', () async {
      await service.sync('alice');
      String? uid = 'alice';
      service.watchTokenRefresh(() => uid);

      tokens.emitRefresh('token-B');
      await Future<void>.delayed(Duration.zero);
      await service.sync('alice'); // drains the serialized queue

      expect(backend.registerCalls.map((c) => c.token), contains('token-B'));
      expect((await store.lastRegistered())?.token, 'token-B');
    });

    test('ignores a refresh while signed out', () async {
      service.watchTokenRefresh(() => null);
      tokens.emitRefresh('token-B');
      await Future<void>.delayed(Duration.zero);
      expect(backend.registerCalls, isEmpty);
    });

    test(
      'watchTokenRefresh again replaces (does not duplicate) the subscription',
      () async {
        service.watchTokenRefresh(() => 'alice');
        service.watchTokenRefresh(() => 'alice');
        tokens.emitRefresh('token-B');
        await Future<void>.delayed(Duration.zero);
        await service.sync('alice');
        expect(
          backend.registerCalls.where((c) => c.token == 'token-B'),
          hasLength(1),
        );
      },
    );
  });

  group('unregisterCurrentDevice (before signOut)', () {
    test(
      'removes the server doc, deletes the local FCM token, forgets the registration',
      () async {
        await service.sync('alice');

        expect(await service.unregisterCurrentDevice(), isTrue);

        expect(backend.unregisterCalls, ['token-A']);
        expect(tokens.deleteCount, 1);
        expect(await store.lastRegistered(), isNull);
      },
    );

    test('after unregister a different user registers fresh', () async {
      await service.sync('alice');
      await service.unregisterCurrentDevice();
      tokens.token = 'token-C';
      expect(await service.sync('bob'), DeviceRegistrationOutcome.registered);
      expect(backend.registerCalls.last.token, 'token-C');
    });

    test(
      'still invalidates the local token and clears state when the server call fails',
      () async {
        await service.sync('alice');
        backend.unregisterResult = false;

        expect(await service.unregisterCurrentDevice(), isFalse);

        expect(tokens.deleteCount, 1);
        expect(await store.lastRegistered(), isNull);
      },
    );

    test(
      'with nothing registered it makes no server call but still invalidates the token',
      () async {
        expect(await service.unregisterCurrentDevice(), isTrue);
        expect(backend.unregisterCalls, isEmpty);
        expect(tokens.deleteCount, 1);
      },
    );

    test('never throws, even if every collaborator fails', () async {
      await service.sync('alice');
      final failing = DeviceRegistrationService(
        tokens: _ThrowingTokens(),
        backend: _ThrowingBackend(),
        permission: permission,
        store: store,
        clock: () => now,
      );
      expect(await failing.unregisterCurrentDevice(), isFalse);
      expect(await store.lastRegistered(), isNull);
    });
  });

  test(
    'operations are serialized: a logout unregister queued behind a sync sees its result',
    () async {
      final syncFuture = service.sync('alice');
      final unregisterFuture = service.unregisterCurrentDevice();
      await Future.wait([syncFuture, unregisterFuture]);

      // the sync registered first, so the unregister found a token to remove
      expect(backend.registerCalls, hasLength(1));
      expect(backend.unregisterCalls, ['token-A']);
      expect(await store.lastRegistered(), isNull);
    },
  );
}

class _ThrowingTokens extends MockFcmTokenSource {
  @override
  Future<void> deleteToken() async => throw StateError('fcm down');
}

class _ThrowingBackend extends MockDeviceRegistrationBackend {
  @override
  Future<bool> unregister({required String token}) async =>
      throw StateError('network down');
}
