import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/notifications/models/notification_prefs.dart';
import 'package:twin_ar/features/notifications/repositories/mock_notification_settings_repository.dart';
import 'package:twin_ar/features/notifications/services/mock_notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_permission_service.dart';
import 'package:twin_ar/features/notifications/viewmodels/notification_settings_viewmodel.dart';
import 'package:twin_ar/features/notifications/views/notification_settings_view.dart';

void main() {
  late MockNotificationSettingsRepository repo;
  late MockNotificationPermissionService permission;

  Future<NotificationSettingsViewModel> pump(
    WidgetTester tester, {
    bool admin = false,
  }) async {
    final vm = NotificationSettingsViewModel(
      repository: repo,
      permission: permission,
      uid: admin ? 'admin-uid' : 'alice',
      isAdmin: admin,
    )..load();
    await tester.pumpWidget(
      ChangeNotifierProvider<NotificationSettingsViewModel>.value(
        value: vm,
        child: const MaterialApp(home: NotificationSettingsView()),
      ),
    );
    await tester.pump();
    await tester.pump();
    return vm;
  }

  setUp(() {
    repo = MockNotificationSettingsRepository();
    permission = MockNotificationPermissionService();
  });

  testWidgets(
    'customer sees Order updates + Reviews switches (no admin switches) and the inbox note',
    (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('switch_orders')), findsOneWidget);
      expect(find.byKey(const Key('switch_reviews')), findsOneWidget);
      expect(find.byKey(const Key('switch_admin_orders')), findsNothing);
      expect(
        find.byKey(const Key('notification_settings_inbox_note')),
        findsOneWidget,
      );
      expect(
        find.textContaining('Notification Centre still keeps a record'),
        findsOneWidget,
      );
    },
  );

  testWidgets('admin sees the four admin switches and no customer switches', (
    tester,
  ) async {
    await pump(tester, admin: true);
    for (final k in [
      'switch_admin_orders',
      'switch_admin_stock',
      'switch_admin_moderation',
      'switch_admin_payments',
    ]) {
      expect(find.byKey(Key(k)), findsOneWidget, reason: k);
    }
    expect(find.byKey(const Key('switch_orders')), findsNothing);
    expect(find.byKey(const Key('switch_reviews')), findsNothing);
    expect(
      find.byKey(const Key('notification_settings_inbox_note')),
      findsNothing,
    );
  });

  testWidgets(
    'D7: turning Order updates off saves immediately with the customer keys',
    (tester) async {
      await pump(tester);
      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('switch_orders')))
            .value,
        isTrue,
      );

      await tester.tap(find.byKey(const Key('switch_orders')));
      await tester.pump();
      await tester.pump();

      expect(
        tester
            .widget<SwitchListTile>(find.byKey(const Key('switch_orders')))
            .value,
        isFalse,
      );
      expect(repo.saves.single.prefs.pushOrders, isFalse);
      expect(repo.saves.single.isAdmin, isFalse);
    },
  );

  testWidgets('saved preferences are shown when the screen opens', (
    tester,
  ) async {
    repo.stored = const NotificationPrefs(
      pushOrders: false,
      pushReviews: false,
    );
    await pump(tester);
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('switch_orders')))
          .value,
      isFalse,
    );
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('switch_reviews')))
          .value,
      isFalse,
    );
  });

  testWidgets('a failed save rolls the switch back and shows an error', (
    tester,
  ) async {
    await pump(tester);
    repo.failSave = true;
    await tester.tap(find.byKey(const Key('switch_reviews')));
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<SwitchListTile>(find.byKey(const Key('switch_reviews')))
          .value,
      isTrue,
    );
    expect(
      find.byKey(const Key('notification_settings_save_error')),
      findsOneWidget,
    );
  });

  testWidgets('permission card: allowed state has no action', (tester) async {
    await pump(tester);
    expect(
      find.text('Notifications are allowed on this phone.'),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('notification_settings_turn_on')),
      findsNothing,
    );
  });

  testWidgets(
    'permission card: off state offers Turn on, which requests the OS permission',
    (tester) async {
      permission.current = NotificationPermissionStatus.denied;
      permission.afterRequest = NotificationPermissionStatus.granted;
      await pump(tester);
      expect(find.text('Notifications are off on this phone.'), findsOneWidget);
      await tester.tap(find.byKey(const Key('notification_settings_turn_on')));
      await tester.pump();
      await tester.pump();
      expect(permission.requestCount, 1);
      expect(
        find.text('Notifications are allowed on this phone.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('permission card: blocked state offers Open settings', (
    tester,
  ) async {
    permission.current = NotificationPermissionStatus.blocked;
    await pump(tester);
    expect(find.textContaining('blocked'), findsOneWidget);
    await tester.tap(find.text('Open settings'));
    await tester.pump();
    expect(permission.openSettingsCount, 1);
  });

  testWidgets('load failure shows the design-system error state with retry', (
    tester,
  ) async {
    repo.failLoad = true;
    await pump(tester);
    expect(
      find.textContaining("couldn't load your notification settings"),
      findsOneWidget,
    );
    repo.failLoad = false;
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pump();
    expect(find.byKey(const Key('switch_orders')), findsOneWidget);
  });

  testWidgets('states honestly that delivery is not guaranteed', (
    tester,
  ) async {
    await pump(tester);
    await tester.scrollUntilVisible(find.textContaining('not guaranteed'), 100);
    expect(find.textContaining('not guaranteed'), findsOneWidget);
  });
}
