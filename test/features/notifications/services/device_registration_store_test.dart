import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/features/notifications/services/device_registration_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('install id is a stable 32-char hex generated once', () async {
    final store = DeviceRegistrationStore();
    final a = await store.installId();
    final b = await store.installId();
    expect(a, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(b, a);
    // a fresh store instance on the same prefs sees the same id
    expect(await DeviceRegistrationStore().installId(), a);
  });

  test(
    'install id satisfies the server validation (<=64 chars, safe charset)',
    () async {
      final id = await DeviceRegistrationStore().installId();
      expect(id.length, lessThanOrEqualTo(64));
      expect(id, matches(RegExp(r'^[A-Za-z0-9_.+\- ]+$')));
    },
  );

  test('registration round-trips and clears', () async {
    final store = DeviceRegistrationStore();
    expect(await store.lastRegistered(), isNull);
    await store.saveRegistered(
      const RegisteredDevice(uid: 'alice', token: 't1', registeredAtMs: 42),
    );
    final saved = await store.lastRegistered();
    expect(saved?.uid, 'alice');
    expect(saved?.token, 't1');
    expect(saved?.registeredAtMs, 42);
    await store.clearRegistered();
    expect(await store.lastRegistered(), isNull);
    // clearing the registration must not rotate the install id
    final id = await store.installId();
    await store.clearRegistered();
    expect(await store.installId(), id);
  });

  test('a partial/corrupt registration reads as null', () async {
    SharedPreferences.setMockInitialValues({
      'notif_registered_uid': 'alice',
      'notif_registered_token': 't1',
    });
    expect(await DeviceRegistrationStore().lastRegistered(), isNull);
  });

  test('prompt-declined flag defaults to false and persists', () async {
    final store = DeviceRegistrationStore();
    expect(await store.promptDeclined(), isFalse);
    await store.setPromptDeclined(true);
    expect(await store.promptDeclined(), isTrue);
    await store.setPromptDeclined(false);
    expect(await store.promptDeclined(), isFalse);
  });
}
