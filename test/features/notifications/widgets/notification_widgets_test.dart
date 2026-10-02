import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/widgets/feedback/app_toast.dart';
import 'package:twin_ar/core/widgets/navigation/customer_header.dart';
import 'package:twin_ar/features/notifications/widgets/notification_permission_sheet.dart';

void main() {
  group('CustomerHeader bell', () {
    Future<List<String>> pumpHeader(
      WidgetTester tester, {
      int? notificationCount,
      int cartCount = 0,
    }) async {
      final pushed = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          onGenerateRoute: (s) {
            if (s.name == '/') {
              return MaterialPageRoute(
                builder: (_) => Scaffold(
                  body: CustomerHeader(
                    cartCount: cartCount,
                    notificationCount: notificationCount,
                  ),
                ),
              );
            }
            pushed.add(s.name!);
            return MaterialPageRoute(builder: (_) => const Scaffold());
          },
        ),
      );
      return pushed;
    }

    testWidgets(
      'null count hides the bell (cart screen / trees without an inbox)',
      (tester) async {
        await pumpHeader(tester);
        expect(
          find.byKey(const Key('customer_notifications_bell')),
          findsNothing,
        );
        // existing icons are untouched
        expect(find.byIcon(Icons.favorite_border), findsOneWidget);
        expect(find.byIcon(Icons.shopping_cart_outlined), findsOneWidget);
      },
    );

    testWidgets('zero shows the bell without a badge', (tester) async {
      await pumpHeader(tester, notificationCount: 0);
      expect(
        find.byKey(const Key('customer_notifications_bell')),
        findsOneWidget,
      );
      expect(
        find.byKey(const Key('customer_notification_badge')),
        findsNothing,
      );
    });

    testWidgets('a count shows the badge; above 9 it reads 9+', (tester) async {
      await pumpHeader(tester, notificationCount: 3);
      expect(
        find.byKey(const Key('customer_notification_badge')),
        findsOneWidget,
      );
      expect(find.text('3'), findsOneWidget);

      await tester.pumpWidget(const SizedBox()); // fresh route state
      await pumpHeader(tester, notificationCount: 10);
      await tester.pump();
      expect(find.text('9+'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      await pumpHeader(tester, notificationCount: 50);
      await tester.pump();
      expect(find.text('9+'), findsOneWidget);
    });

    testWidgets('the cart badge and the notification badge are independent', (
      tester,
    ) async {
      await pumpHeader(tester, notificationCount: 2, cartCount: 7);
      expect(find.text('2'), findsOneWidget);
      expect(find.text('7'), findsOneWidget);
    });

    testWidgets('tapping the bell opens the Notification Centre route', (
      tester,
    ) async {
      final pushed = await pumpHeader(tester, notificationCount: 1);
      await tester.tap(find.byKey(const Key('customer_notifications_bell')));
      await tester.pumpAndSettle();
      expect(pushed, [RouteNames.notifications]);
    });

    testWidgets('the tooltip announces the unread count', (tester) async {
      await pumpHeader(tester, notificationCount: 4);
      final btn = tester.widget<IconButton>(
        find.byKey(const Key('customer_notifications_bell')),
      );
      expect(btn.tooltip, 'Notifications, 4 unread');
    });
  });

  group('NotificationPermissionSheet', () {
    Future<bool?> openSheet(
      WidgetTester tester, {
      required bool admin,
      required Future<void> Function() act,
    }) async {
      bool? result;
      var done = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () async {
                    result = await showNotificationPermissionSheet(
                      context,
                      admin: admin,
                    );
                    done = true;
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('open'));
      await tester.pumpAndSettle();
      await act();
      await tester.pumpAndSettle();
      expect(done, isTrue);
      return result;
    }

    testWidgets('customer copy, "Turn on" => true', (tester) async {
      final r = await openSheet(
        tester,
        admin: false,
        act: () async {
          expect(find.text('Get order updates'), findsOneWidget);
          expect(
            find.textContaining('only message you about your orders'),
            findsOneWidget,
          );
          await tester.tap(
            find.byKey(const Key('notification_permission_turn_on')),
          );
        },
      );
      expect(r, isTrue);
    });

    testWidgets('admin copy, "Not now" => false', (tester) async {
      final r = await openSheet(
        tester,
        admin: true,
        act: () async {
          expect(find.text('Get store alerts'), findsOneWidget);
          expect(find.textContaining('new orders, low stock'), findsOneWidget);
          await tester.tap(
            find.byKey(const Key('notification_permission_not_now')),
          );
        },
      );
      expect(r, isFalse);
    });

    testWidgets(
      'dismissing the sheet resolves to null (treated as "not now")',
      (tester) async {
        bool? result = true;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () async {
                    result = await showNotificationPermissionSheet(
                      context,
                      admin: false,
                    );
                  },
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        await tester.tapAt(const Offset(10, 10)); // scrim
        await tester.pumpAndSettle();
        expect(result, isNull);
      },
    );
  });

  group('AppToast.notification', () {
    testWidgets(
      'shows a bold title over the message and calls onTap once then dismisses',
      (tester) async {
        var taps = 0;
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => AppToast.notification(
                    context,
                    title: 'Order shipped',
                    message: 'Order #AB12 is on its way.',
                    onTap: () => taps++,
                  ),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Order shipped'), findsOneWidget);
        expect(find.text('Order #AB12 is on its way.'), findsOneWidget);

        await tester.tap(find.text('Order shipped'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(taps, 1);
        await tester.pump(const Duration(seconds: 6));
        await tester.pumpAndSettle();
        expect(find.text('Order shipped'), findsNothing);
      },
    );

    testWidgets(
      'existing status toasts are unchanged (no title, not tappable, 3s)',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Builder(
              builder: (context) => Scaffold(
                body: ElevatedButton(
                  onPressed: () => AppToast.success(context, 'Saved'),
                  child: const Text('go'),
                ),
              ),
            ),
          ),
        );
        await tester.tap(find.text('go'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(find.text('Saved'), findsOneWidget);
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
        expect(find.text('Saved'), findsNothing);
      },
    );
  });
}
