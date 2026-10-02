import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/features/notifications/models/notification_payload.dart';
import 'package:twin_ar/features/notifications/models/notification_type.dart';
import 'package:twin_ar/features/notifications/services/notification_navigator.dart';
import 'package:twin_ar/features/notifications/services/notification_route_tracker.dart';
import 'package:twin_ar/features/notifications/services/notification_router.dart';

NotificationPayload _shipped({String uid = 'alice', String order = 'ord_1'}) =>
    NotificationPayload(
      type: NotificationPayloadType.orderShipped,
      recipientUid: uid,
      orderId: order,
      notificationId: 'order_shipped_$order',
    );

void main() {
  late GlobalKey<NavigatorState> key;
  late NotificationRouteTracker tracker;
  late NotificationSession session;
  late DateTime now;
  late NotificationNavigator navigator;
  late List<NotificationPayload> opened;

  setUp(() {
    key = GlobalKey<NavigatorState>();
    tracker = NotificationRouteTracker();
    session = const NotificationSession(
      uid: 'alice',
      isCustomer: true,
      isSuperAdmin: false,
    );
    now = DateTime(2026, 10, 2, 12);
    opened = [];
    navigator = NotificationNavigator(
      navigatorKey: key,
      tracker: tracker,
      session: () => session,
      onOpened: opened.add,
      clock: () => now,
    );
  });

  tearDown(() => navigator.dispose());

  Future<void> pumpApp(
    WidgetTester tester, {
    String initial = RouteNames.splash,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        navigatorKey: key,
        navigatorObservers: [tracker],
        initialRoute: initial,
        onGenerateRoute: (settings) => MaterialPageRoute(
          settings: settings,
          builder: (_) => Scaffold(
            body: Center(child: Text('${settings.name}|${settings.arguments}')),
          ),
        ),
      ),
    );
  }

  testWidgets(
    'a tap while the app is already on a real screen opens at once, ON TOP of the stack',
    (tester) async {
      await pumpApp(tester, initial: RouteNames.home);
      await tester.pump();

      navigator.open(_shipped());
      await tester.pumpAndSettle();

      expect(find.text('${RouteNames.orderDetail}|ord_1'), findsOneWidget);
      expect(opened, hasLength(1));
      expect(navigator.hasPending, isFalse);

      // Back returns to Home (pushed, never replaced)
      key.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('${RouteNames.home}|null'), findsOneWidget);
    },
  );

  testWidgets(
    'a cold-start tap is HELD during Splash and opens after the app routes to Home',
    (tester) async {
      await pumpApp(tester); // splash
      await tester.pump();

      navigator.open(_shipped());
      await tester.pumpAndSettle();
      expect(navigator.hasPending, isTrue);
      expect(find.text('${RouteNames.orderDetail}|ord_1'), findsNothing);
      expect(opened, isEmpty);

      key.currentState!.pushReplacementNamed(RouteNames.home);
      await tester.pumpAndSettle();

      expect(find.text('${RouteNames.orderDetail}|ord_1'), findsOneWidget);
      expect(navigator.hasPending, isFalse);
      expect(opened.single.orderId, 'ord_1');
    },
  );

  testWidgets(
    'login / onboarding / sign-up / forgot-password also hold the tap',
    (tester) async {
      for (final name in [
        RouteNames.onboarding,
        RouteNames.login,
        RouteNames.signUp,
        RouteNames.forgotPassword,
      ]) {
        tracker.debugReset();
        navigator = NotificationNavigator(
          navigatorKey: key,
          tracker: tracker,
          session: () => session,
          clock: () => now,
        );
        await pumpApp(tester, initial: name);
        await tester.pump();
        navigator.open(_shipped());
        await tester.pumpAndSettle();
        expect(navigator.hasPending, isTrue, reason: name);
        navigator.dispose();
      }
    },
  );

  testWidgets(
    'a tap held through a login as a DIFFERENT user is dropped, never shown to them',
    (tester) async {
      await pumpApp(tester, initial: RouteNames.login);
      await tester.pump();
      navigator.open(_shipped(uid: 'alice'));
      await tester.pumpAndSettle();
      expect(navigator.hasPending, isTrue);

      session = const NotificationSession(
        uid: 'bob',
        isCustomer: true,
        isSuperAdmin: false,
      );
      key.currentState!.pushReplacementNamed(RouteNames.home);
      await tester.pumpAndSettle();

      expect(navigator.hasPending, isFalse);
      expect(find.text('${RouteNames.orderDetail}|ord_1'), findsNothing);
      expect(opened, isEmpty);
    },
  );

  testWidgets('a held tap expires after 2 minutes', (tester) async {
    await pumpApp(tester, initial: RouteNames.login);
    await tester.pump();
    navigator.open(_shipped());
    await tester.pumpAndSettle();
    expect(navigator.hasPending, isTrue);

    now = now.add(
      NotificationNavigator.maxPendingAge + const Duration(seconds: 1),
    );
    key.currentState!.pushReplacementNamed(RouteNames.home);
    await tester.pumpAndSettle();

    expect(navigator.hasPending, isFalse);
    expect(find.text('${RouteNames.orderDetail}|ord_1'), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('an admin destination is never opened for a customer session', (
    tester,
  ) async {
    await pumpApp(tester, initial: RouteNames.home);
    await tester.pump();
    navigator.open(
      const NotificationPayload(
        type: NotificationPayloadType.adminNewOrder,
        recipientUid: null,
        orderId: 'ord_1',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('${RouteNames.adminOrderDetail}|ord_1'), findsNothing);
    expect(opened, isEmpty);
  });

  testWidgets('an admin push opens the admin destination for a superAdmin', (
    tester,
  ) async {
    session = const NotificationSession(
      uid: 'admin-uid',
      isCustomer: false,
      isSuperAdmin: true,
    );
    await pumpApp(tester, initial: RouteNames.adminDashboard);
    await tester.pump();
    navigator.open(
      const NotificationPayload(
        type: NotificationPayloadType.adminLowStock,
        recipientUid: null,
        productId: 'p1',
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('${RouteNames.adminInventory}|null'), findsOneWidget);
  });

  testWidgets('isShowing is true only when already on that exact destination', (
    tester,
  ) async {
    await pumpApp(tester, initial: RouteNames.home);
    await tester.pump();
    expect(navigator.isShowing(_shipped()), isFalse);

    key.currentState!.pushNamed(RouteNames.orderDetail, arguments: 'ord_1');
    await tester.pumpAndSettle();
    expect(navigator.isShowing(_shipped(order: 'ord_1')), isTrue);
    expect(navigator.isShowing(_shipped(order: 'ord_2')), isFalse);
    expect(navigator.isShowing(_shipped(uid: 'bob')), isFalse);
  });

  testWidgets('the tracker ignores unnamed routes (dialogs) and follows pops', (
    tester,
  ) async {
    await pumpApp(tester, initial: RouteNames.home);
    await tester.pump();
    expect(tracker.currentName, RouteNames.home);

    final ctx = key.currentState!.overlay!.context;
    showDialog<void>(
      context: ctx,
      builder: (_) => const AlertDialog(title: Text('d')),
    );
    await tester.pumpAndSettle();
    expect(tracker.currentName, RouteNames.home);

    key.currentState!.pop(); // close dialog
    await tester.pumpAndSettle();
    key.currentState!.pushNamed(RouteNames.orders);
    await tester.pumpAndSettle();
    expect(tracker.currentName, RouteNames.orders);
    key.currentState!.pop();
    await tester.pumpAndSettle();
    expect(tracker.currentName, RouteNames.home);
  });
}
