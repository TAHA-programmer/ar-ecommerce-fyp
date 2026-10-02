import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/features/notifications/models/app_notification.dart';
import 'package:twin_ar/features/notifications/models/notification_payload.dart';
import 'package:twin_ar/features/notifications/models/notification_type.dart';
import 'package:twin_ar/features/notifications/services/notification_router.dart';

const _alice = NotificationSession(
  uid: 'alice',
  isCustomer: true,
  isSuperAdmin: false,
);
const _bob = NotificationSession(
  uid: 'bob',
  isCustomer: true,
  isSuperAdmin: false,
);
const _admin = NotificationSession(
  uid: 'admin-uid',
  isCustomer: false,
  isSuperAdmin: true,
);

NotificationPayload _p(
  NotificationPayloadType type, {
  String? recipientUid = 'alice',
  String? orderId,
  String? reviewId,
  String? productId,
}) => NotificationPayload(
  type: type,
  recipientUid: type.isAdmin ? null : recipientUid,
  orderId: orderId,
  reviewId: reviewId,
  productId: productId,
);

void main() {
  group('NotificationRouter.resolve - destination table', () {
    test('order status types open Order Detail with the order id', () {
      for (final t in [
        NotificationPayloadType.orderPlaced,
        NotificationPayloadType.orderConfirmed,
        NotificationPayloadType.orderShipped,
        NotificationPayloadType.orderDelivered,
        NotificationPayloadType.orderCancelled,
      ]) {
        expect(
          NotificationRouter.resolve(_p(t, orderId: 'ord_1'), _alice),
          const NotificationDestination(RouteNames.orderDetail, 'ord_1'),
          reason: t.wire,
        );
      }
    });

    test('refund opens My Orders; review moderation opens My Reviews', () {
      expect(
        NotificationRouter.resolve(
          _p(NotificationPayloadType.paymentRefunded),
          _alice,
        ),
        const NotificationDestination(RouteNames.orders),
      );
      for (final t in [
        NotificationPayloadType.reviewHidden,
        NotificationPayloadType.reviewRejected,
        NotificationPayloadType.reviewRestored,
      ]) {
        expect(
          NotificationRouter.resolve(_p(t, reviewId: 'r1'), _alice),
          const NotificationDestination(RouteNames.myReviews),
        );
      }
    });

    test('admin types map to the existing Admin routes (plan §4.3)', () {
      expect(
        NotificationRouter.resolve(
          _p(NotificationPayloadType.adminNewOrder, orderId: 'ord_9'),
          _admin,
        ),
        const NotificationDestination(RouteNames.adminOrderDetail, 'ord_9'),
      );
      for (final t in [
        NotificationPayloadType.adminLowStock,
        NotificationPayloadType.adminOutOfStock,
      ]) {
        expect(
          NotificationRouter.resolve(_p(t, productId: 'p1'), _admin),
          const NotificationDestination(RouteNames.adminInventory),
        );
      }
      expect(
        NotificationRouter.resolve(
          _p(NotificationPayloadType.adminReviewFlagged, reviewId: 'r'),
          _admin,
        ),
        const NotificationDestination(RouteNames.adminReviews),
      );
      expect(
        NotificationRouter.resolve(
          _p(NotificationPayloadType.adminPaymentIssue),
          _admin,
        ),
        const NotificationDestination(RouteNames.adminNotifications),
      );
    });
  });

  group('NotificationRouter.resolve - safety checks', () {
    test('signed out => nothing opens', () {
      for (final t in NotificationPayloadType.values) {
        expect(
          NotificationRouter.resolve(
            _p(t, orderId: 'o', reviewId: 'r', productId: 'p'),
            NotificationSession.signedOut,
          ),
          isNull,
          reason: t.wire,
        );
      }
    });

    test(
      'a customer notification for ANOTHER account is dropped (shared device)',
      () {
        final p = _p(NotificationPayloadType.orderShipped, orderId: 'ord_1');
        expect(NotificationRouter.resolve(p, _alice), isNotNull);
        expect(NotificationRouter.resolve(p, _bob), isNull);
      },
    );

    test(
      'an admin is never routed a customer notification, even with a matching uid',
      () {
        final adminAsAlice = const NotificationSession(
          uid: 'alice',
          isCustomer: false,
          isSuperAdmin: true,
        );
        expect(
          NotificationRouter.resolve(
            _p(NotificationPayloadType.orderShipped, orderId: 'ord_1'),
            adminAsAlice,
          ),
          isNull,
        );
      },
    );

    test('a customer can never open an admin destination', () {
      for (final t in NotificationPayloadType.values.where((t) => t.isAdmin)) {
        expect(
          NotificationRouter.resolve(
            _p(t, orderId: 'ord_1', reviewId: 'r', productId: 'p'),
            _alice,
          ),
          isNull,
          reason: t.wire,
        );
      }
    });

    test('a destination needing an order id without one does not navigate', () {
      expect(
        NotificationRouter.resolve(
          _p(NotificationPayloadType.orderShipped),
          _alice,
        ),
        isNull,
      );
      expect(
        NotificationRouter.resolve(
          _p(NotificationPayloadType.adminNewOrder),
          _admin,
        ),
        isNull,
      );
    });

    test(
      'routes only ever come from the table (never from payload content)',
      () {
        final p = _p(
          NotificationPayloadType.orderShipped,
          orderId: '/admin/dashboard',
        );
        // even a path-looking id is only ever an ARGUMENT to orderDetail
        final d = NotificationRouter.resolve(p, _alice)!;
        expect(d.routeName, RouteNames.orderDetail);
        expect(d.arguments, '/admin/dashboard');
      },
    );
  });

  group('NotificationRouter.resolveInboxRow', () {
    AppNotification row(
      String route, {
      String? entity,
      String type = 'order_shipped',
    }) => AppNotification(
      id: 'x',
      type: NotificationType.fromWire(type),
      title: 't',
      body: 'b',
      route: route,
      entityId: entity,
      createdAt: DateTime(2026),
      readAt: null,
    );

    test('maps the server destination enum', () {
      expect(
        NotificationRouter.resolveInboxRow(row('orderDetail', entity: 'ord_1')),
        const NotificationDestination(RouteNames.orderDetail, 'ord_1'),
      );
      expect(
        NotificationRouter.resolveInboxRow(
          row('orders', type: 'payment_refunded'),
        ),
        const NotificationDestination(RouteNames.orders),
      );
      expect(
        NotificationRouter.resolveInboxRow(
          row('myReviews', type: 'review_hidden'),
        ),
        const NotificationDestination(RouteNames.myReviews),
      );
    });

    test(
      'unknown route, missing entity, unknown type, or a path => no navigation',
      () {
        expect(NotificationRouter.resolveInboxRow(row('orderDetail')), isNull);
        expect(
          NotificationRouter.resolveInboxRow(row('orderDetail', entity: '')),
          isNull,
        );
        expect(
          NotificationRouter.resolveInboxRow(row('/admin/dashboard')),
          isNull,
        );
        expect(
          NotificationRouter.resolveInboxRow(row('adminInventory')),
          isNull,
        );
        expect(NotificationRouter.resolveInboxRow(row('')), isNull);
        expect(
          NotificationRouter.resolveInboxRow(
            row('orderDetail', entity: 'o', type: 'from_the_future'),
          ),
          isNull,
        );
      },
    );
  });
}
