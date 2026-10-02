import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/notifications/models/notification_prefs.dart';
import 'package:twin_ar/features/notifications/repositories/mock_notification_settings_repository.dart';
import 'package:twin_ar/features/notifications/services/mock_notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_permission_service.dart';
import 'package:twin_ar/features/notifications/viewmodels/notification_settings_viewmodel.dart';

void main() {
  late MockNotificationSettingsRepository repo;
  late MockNotificationPermissionService permission;

  NotificationSettingsViewModel make({
    bool admin = false,
    String? uid = 'alice',
  }) => NotificationSettingsViewModel(
    repository: repo,
    permission: permission,
    uid: uid,
    isAdmin: admin,
  );

  setUp(() {
    repo = MockNotificationSettingsRepository();
    permission = MockNotificationPermissionService();
  });

  test('load reads prefs and the OS permission', () async {
    repo.stored = const NotificationPrefs(pushOrders: false);
    permission.current = NotificationPermissionStatus.denied;
    final vm = make();
    expect(vm.isLoading, isTrue);
    await vm.load();
    expect(vm.isLoading, isFalse);
    expect(vm.prefs.pushOrders, isFalse);
    expect(vm.permissionStatus, NotificationPermissionStatus.denied);
    expect(vm.permissionGranted, isFalse);
  });

  test('a load failure is surfaced (not silently defaults)', () async {
    repo.failLoad = true;
    final vm = make();
    await vm.load();
    expect(vm.loadFailed, isTrue);
    repo.failLoad = false;
    await vm.load();
    expect(vm.loadFailed, isFalse);
  });

  test(
    'D7: the order switch can be turned off and persists with the customer keys',
    () async {
      final vm = make();
      await vm.load();
      await vm.setPushOrders(false);
      expect(vm.prefs.pushOrders, isFalse);
      expect(repo.saves.single.isAdmin, isFalse);
      expect(repo.saves.single.prefs.pushOrders, isFalse);
      expect(repo.saves.single.uid, 'alice');
    },
  );

  test(
    'an admin save is flagged isAdmin so only admin keys are written',
    () async {
      final vm = make(admin: true, uid: 'admin-uid');
      await vm.load();
      await vm.setPushAdminStock(false);
      expect(repo.saves.single.isAdmin, isTrue);
      expect(repo.saves.single.prefs.pushAdminStock, isFalse);
    },
  );

  test('every setter updates only its own switch', () async {
    final vm = make(admin: true);
    await vm.load();
    await vm.setPushAdminOrders(false);
    await vm.setPushAdminModeration(false);
    await vm.setPushAdminPayments(false);
    expect(vm.prefs.pushAdminOrders, isFalse);
    expect(vm.prefs.pushAdminModeration, isFalse);
    expect(vm.prefs.pushAdminPayments, isFalse);
    expect(vm.prefs.pushAdminStock, isTrue);
    expect(vm.prefs.pushOrders, isTrue);
    await vm.setPushReviews(false);
    expect(vm.prefs.pushReviews, isFalse);
  });

  test(
    'a failed save rolls the switch back and reports an honest error',
    () async {
      final vm = make();
      await vm.load();
      repo.failSave = true;
      await vm.setPushOrders(false);
      expect(vm.prefs.pushOrders, isTrue); // rolled back
      expect(vm.saveError, isNotNull);
      expect(vm.isSaving, isFalse);

      repo.failSave = false;
      await vm.setPushOrders(false);
      expect(vm.saveError, isNull);
      expect(vm.prefs.pushOrders, isFalse);
    },
  );

  test('setting a switch to its current value does not write', () async {
    final vm = make();
    await vm.load();
    await vm.setPushOrders(true);
    expect(repo.saves, isEmpty);
  });

  test('no uid (signed out) never writes', () async {
    final vm = make(uid: null);
    await vm.load();
    await vm.setPushOrders(false);
    expect(repo.saves, isEmpty);
  });

  test(
    'turnOnNotifications: denied requests, blocked opens system settings',
    () async {
      permission.current = NotificationPermissionStatus.denied;
      permission.afterRequest = NotificationPermissionStatus.granted;
      final vm = make();
      await vm.load();
      await vm.turnOnNotifications();
      expect(permission.requestCount, 1);
      expect(vm.permissionGranted, isTrue);

      permission.current = NotificationPermissionStatus.blocked;
      final vm2 = make();
      await vm2.load();
      await vm2.turnOnNotifications();
      expect(permission.openSettingsCount, 1);
    },
  );

  test(
    'refreshPermission re-reads the OS state (returning from system settings)',
    () async {
      permission.current = NotificationPermissionStatus.blocked;
      final vm = make();
      await vm.load();
      expect(vm.permissionGranted, isFalse);
      permission.current = NotificationPermissionStatus.granted;
      await vm.refreshPermission();
      expect(vm.permissionGranted, isTrue);
    },
  );

  test('disposing mid-save does not throw', () async {
    final vm = make();
    await vm.load();
    final f = vm.setPushOrders(false);
    vm.dispose();
    await f;
  });
}
