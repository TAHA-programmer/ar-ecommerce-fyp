import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/features/notifications/models/app_notification.dart';
import 'package:twin_ar/features/notifications/models/notification_type.dart';
import 'package:twin_ar/features/notifications/repositories/mock_notification_inbox_repository.dart';
import 'package:twin_ar/features/notifications/repositories/notification_inbox_repository.dart';
import 'package:twin_ar/features/notifications/services/mock_notification_permission_service.dart';
import 'package:twin_ar/features/notifications/services/notification_permission_service.dart';
import 'package:twin_ar/features/notifications/views/notifications_view.dart';
import 'package:twin_ar/features/notifications/widgets/notification_tile.dart';

final _now = DateTime(2026, 10, 2, 12);

AppNotification _n(
  String id, {
  required DateTime at,
  bool read = false,
  String type = 'order_shipped',
  String route = 'orderDetail',
  String? entity = 'ord_1',
  String title = 'Order shipped',
}) => AppNotification(
  id: id,
  type: NotificationType.fromWire(type),
  title: title,
  body: 'Body of $id',
  route: route,
  entityId: entity,
  createdAt: at,
  readAt: read ? at : null,
);

void main() {
  late List<RouteSettings> pushed;

  Widget host(
    MockNotificationInboxRepository repo, {
    MockNotificationPermissionService? permission,
  }) {
    pushed = [];
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<NotificationInboxRepository>.value(value: repo),
        Provider<NotificationPermissionService>.value(
          value:
              permission ??
              MockNotificationPermissionService(
                current: NotificationPermissionStatus.granted,
              ),
        ),
      ],
      child: MaterialApp(
        onGenerateRoute: (settings) {
          if (settings.name == '/') {
            return MaterialPageRoute(
              settings: settings,
              builder: (_) => NotificationsView(clock: () => _now),
            );
          }
          pushed.add(settings);
          return MaterialPageRoute(
            settings: settings,
            builder: (_) => Scaffold(body: Text('PUSHED ${settings.name}')),
          );
        },
      ),
    );
  }

  testWidgets('loading state while the first snapshot has not arrived', (
    tester,
  ) async {
    final repo = MockNotificationInboxRepository(isLoading: true);
    await tester.pumpWidget(host(repo));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('No notifications yet'), findsNothing);
  });

  testWidgets('empty state uses the design-system empty widget', (
    tester,
  ) async {
    await tester.pumpWidget(host(MockNotificationInboxRepository()));
    await tester.pump();
    expect(find.text('No notifications yet'), findsOneWidget);
    expect(
      find.text('Order updates and account alerts will appear here.'),
      findsOneWidget,
    );
    expect(find.byKey(const Key('notifications_mark_all_read')), findsNothing);
  });

  testWidgets('error state with retry when nothing is loaded', (tester) async {
    final repo = MockNotificationInboxRepository(hasError: true);
    await tester.pumpWidget(host(repo));
    await tester.pump();
    expect(
      find.textContaining("couldn't load your notifications"),
      findsOneWidget,
    );
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(repo.retryCount, 1);
  });

  testWidgets(
    'a transient error keeps the last-known list visible (never a fake empty state)',
    (tester) async {
      final repo = MockNotificationInboxRepository(
        initial: [_n('a', at: _now.subtract(const Duration(minutes: 5)))],
      );
      await tester.pumpWidget(host(repo));
      repo.setError(true);
      await tester.pump();
      expect(find.text('Body of a'), findsOneWidget);
      expect(find.textContaining("couldn't load"), findsNothing);
    },
  );

  testWidgets('lists rows newest first grouped by day, unread highlighted', (
    tester,
  ) async {
    final repo = MockNotificationInboxRepository(
      initial: [
        _n('today', at: _now.subtract(const Duration(hours: 1))),
        _n('yesterday', at: _now.subtract(const Duration(days: 1)), read: true),
        _n('older', at: DateTime(2026, 9, 20, 9), read: true),
      ],
    );
    await tester.pumpWidget(host(repo));
    await tester.pump();

    expect(find.text('Today'), findsOneWidget);
    // the day header AND the row relative time both read "Yesterday"
    expect(find.text('Yesterday'), findsNWidgets(2));
    expect(find.text('September 20'), findsOneWidget);
    expect(find.byType(NotificationTile), findsNWidgets(3));
    // only the unread row has the dot
    expect(find.byKey(const Key('notification_unread_dot')), findsOneWidget);
    final order = tester
        .widgetList<NotificationTile>(find.byType(NotificationTile))
        .map((t) => t.notification.id)
        .toList();
    expect(order, ['today', 'yesterday', 'older']);
  });

  testWidgets('tapping a row marks it read and opens its destination', (
    tester,
  ) async {
    final repo = MockNotificationInboxRepository(
      initial: [
        _n(
          'a',
          at: _now.subtract(const Duration(minutes: 5)),
          entity: 'ord_77',
        ),
      ],
    );
    await tester.pumpWidget(host(repo));
    await tester.pump();
    expect(repo.unreadCount, 1);

    await tester.tap(find.text('Body of a'));
    await tester.pumpAndSettle();

    expect(repo.unreadCount, 0);
    expect(pushed.single.name, RouteNames.orderDetail);
    expect(pushed.single.arguments, 'ord_77');
  });

  testWidgets(
    'a row with no resolvable destination only marks read (no navigation)',
    (tester) async {
      final repo = MockNotificationInboxRepository(
        initial: [_n('a', at: _now, route: '/admin/dashboard')],
      );
      await tester.pumpWidget(host(repo));
      await tester.pump();
      await tester.tap(find.text('Body of a'));
      await tester.pumpAndSettle();
      expect(repo.unreadCount, 0);
      expect(pushed, isEmpty);
    },
  );

  testWidgets('refund and review rows route to Orders / My Reviews', (
    tester,
  ) async {
    final repo = MockNotificationInboxRepository(
      initial: [
        _n(
          'r',
          at: _now,
          type: 'payment_refunded',
          route: 'orders',
          entity: null,
          title: 'Payment refunded',
        ),
        _n(
          'v',
          at: _now.subtract(const Duration(minutes: 1)),
          type: 'review_hidden',
          route: 'myReviews',
          entity: 'u_p',
          title: 'Review hidden',
        ),
      ],
    );
    await tester.pumpWidget(host(repo));
    await tester.pump();
    await tester.tap(find.text('Body of r'));
    await tester.pumpAndSettle();
    expect(pushed.last.name, RouteNames.orders);
    Navigator.of(
      tester.element(find.text('PUSHED ${RouteNames.orders}')),
    ).pop();
    await tester.pumpAndSettle();
    await tester.tap(find.text('Body of v'));
    await tester.pumpAndSettle();
    expect(pushed.last.name, RouteNames.myReviews);
  });

  testWidgets('"Mark all read" appears only with unread rows and clears them', (
    tester,
  ) async {
    final repo = MockNotificationInboxRepository(
      initial: [
        _n('a', at: _now),
        _n('b', at: _now.subtract(const Duration(minutes: 1))),
      ],
    );
    await tester.pumpWidget(host(repo));
    await tester.pump();
    expect(
      find.byKey(const Key('notifications_mark_all_read')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const Key('notifications_mark_all_read')));
    await tester.pumpAndSettle();
    expect(repo.unreadCount, 0);
    expect(find.byKey(const Key('notifications_mark_all_read')), findsNothing);
  });

  testWidgets('a failed "Mark all read" tells the user and changes nothing', (
    tester,
  ) async {
    final repo = MockNotificationInboxRepository(initial: [_n('a', at: _now)])
      ..failWrites = true;
    await tester.pumpWidget(host(repo));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notifications_mark_all_read')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(repo.unreadCount, 1);
    expect(
      find.textContaining("Couldn't update your notifications"),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets('swipe-to-dismiss deletes the row', (tester) async {
    final repo = MockNotificationInboxRepository(
      initial: [
        _n('a', at: _now),
        _n('b', at: _now.subtract(const Duration(minutes: 1))),
      ],
    );
    await tester.pumpWidget(host(repo));
    await tester.pump();

    await tester.drag(find.text('Body of a'), const Offset(-600, 0));
    await tester.pumpAndSettle();

    expect(find.text('Body of a'), findsNothing);
    expect(find.text('Body of b'), findsOneWidget);
    expect(repo.notifications.map((n) => n.id), ['b']);
  });

  testWidgets('a failed delete restores the row and tells the user', (
    tester,
  ) async {
    final repo = MockNotificationInboxRepository(initial: [_n('a', at: _now)])
      ..failWrites = true;
    await tester.pumpWidget(host(repo));
    await tester.pump();
    await tester.drag(find.text('Body of a'), const Offset(-600, 0));
    await tester.pumpAndSettle();
    expect(find.text('Body of a'), findsOneWidget);
    expect(find.textContaining("Couldn't remove"), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
  });

  testWidgets(
    'shows the "notifications are off" banner when the OS permission is not granted - dismissible',
    (tester) async {
      final repo = MockNotificationInboxRepository(
        initial: [_n('a', at: _now)],
      );
      await tester.pumpWidget(
        host(
          repo,
          permission: MockNotificationPermissionService(
            current: NotificationPermissionStatus.denied,
          ),
        ),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('notification_permission_banner')),
        findsOneWidget,
      );
      expect(find.text('Turn on'), findsOneWidget);
      // the inbox itself is still fully usable
      expect(find.text('Body of a'), findsOneWidget);

      await tester.tap(
        find.byKey(const Key('notification_permission_banner_dismiss')),
      );
      await tester.pump();
      expect(
        find.byKey(const Key('notification_permission_banner')),
        findsNothing,
      );
    },
  );

  testWidgets(
    'no banner when granted; a blocked state offers "Open settings"',
    (tester) async {
      final repo = MockNotificationInboxRepository(
        initial: [_n('a', at: _now)],
      );
      await tester.pumpWidget(host(repo));
      await tester.pump();
      expect(
        find.byKey(const Key('notification_permission_banner')),
        findsNothing,
      );

      await tester.pumpWidget(const SizedBox()); // fresh State
      await tester.pumpWidget(
        host(
          repo,
          permission: MockNotificationPermissionService(
            current: NotificationPermissionStatus.blocked,
          ),
        ),
      );
      await tester.pump();
      expect(find.text('Open settings'), findsOneWidget);
    },
  );

  testWidgets('the gear opens Notification settings; back pops', (
    tester,
  ) async {
    await tester.pumpWidget(host(MockNotificationInboxRepository()));
    await tester.pump();
    await tester.tap(find.byKey(const Key('notifications_settings_button')));
    await tester.pumpAndSettle();
    expect(pushed.single.name, RouteNames.notificationSettings);
  });

  group('time helpers', () {
    final now = DateTime(2026, 10, 2, 12);
    test('relativeNotificationTime', () {
      expect(
        relativeNotificationTime(
          now.subtract(const Duration(seconds: 20)),
          now,
        ),
        'Just now',
      );
      expect(
        relativeNotificationTime(now.subtract(const Duration(minutes: 5)), now),
        '5m',
      );
      expect(
        relativeNotificationTime(now.subtract(const Duration(hours: 3)), now),
        '3h',
      );
      expect(
        relativeNotificationTime(DateTime(2026, 10, 1, 20), now),
        'Yesterday',
      );
      expect(relativeNotificationTime(DateTime(2026, 9, 4, 8), now), 'Sep 4');
      expect(
        relativeNotificationTime(DateTime(2025, 12, 31, 8), now),
        'Dec 31, 2025',
      );
    });
    test('notificationDayLabel', () {
      expect(notificationDayLabel(now, now), 'Today');
      expect(notificationDayLabel(DateTime(2026, 10, 1, 1), now), 'Yesterday');
      expect(notificationDayLabel(DateTime(2026, 8, 3), now), 'August 3');
      expect(notificationDayLabel(DateTime(2025, 8, 3), now), 'August 3, 2025');
    });
  });
}
