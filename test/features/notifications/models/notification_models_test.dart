import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/notifications/models/app_notification.dart';
import 'package:twin_ar/features/notifications/models/notification_payload.dart';
import 'package:twin_ar/features/notifications/models/notification_prefs.dart';
import 'package:twin_ar/features/notifications/models/notification_type.dart';

Map<String, dynamic> _customer(String type, {Map<String, dynamic>? extra}) => {
  'v': '1',
  'type': type,
  'audience': 'customer',
  'recipientUid': 'alice',
  ...?extra,
};

Map<String, dynamic> _admin(String type, {Map<String, dynamic>? extra}) => {
  'v': '1',
  'type': type,
  'audience': 'admin',
  ...?extra,
};

void main() {
  group('NotificationPayload.tryParse (strict)', () {
    test('accepts every customer and admin type with the documented shape', () {
      for (final t in NotificationPayloadType.values) {
        final data = t.isAdmin ? _admin(t.wire) : _customer(t.wire);
        final p = NotificationPayload.tryParse(data);
        expect(p, isNotNull, reason: t.wire);
        expect(p!.type, t);
        expect(p.recipientUid, t.isAdmin ? isNull : 'alice');
      }
    });

    test('reads entity ids and the inbox row id', () {
      final p = NotificationPayload.tryParse(
        _customer(
          'order_shipped',
          extra: {'orderId': 'ord_abc123', 'notificationId': 'order_shipped_x'},
        ),
      );
      expect(p?.orderId, 'ord_abc123');
      expect(p?.notificationId, 'order_shipped_x');
    });

    test('rejects null, wrong version, unknown type', () {
      expect(NotificationPayload.tryParse(null), isNull);
      expect(NotificationPayload.tryParse({}), isNull);
      expect(
        NotificationPayload.tryParse({..._customer('order_shipped'), 'v': '2'}),
        isNull,
      );
      expect(
        NotificationPayload.tryParse({..._customer('order_shipped'), 'v': 1}),
        isNull,
      );
      expect(NotificationPayload.tryParse(_customer('teleport')), isNull);
      expect(
        NotificationPayload.tryParse({
          ..._customer('order_shipped'),
          'type': 5,
        }),
        isNull,
      );
    });

    test('audience must agree with the type', () {
      expect(
        NotificationPayload.tryParse({
          ..._customer('order_shipped'),
          'audience': 'admin',
        }),
        isNull,
      );
      expect(
        NotificationPayload.tryParse({
          ..._admin('admin_new_order'),
          'audience': 'customer',
        }),
        isNull,
      );
      expect(
        NotificationPayload.tryParse(
          {..._customer('order_shipped')}..remove('audience'),
        ),
        isNull,
      );
    });

    test('a customer payload without recipientUid is rejected', () {
      final data = _customer('order_shipped')..remove('recipientUid');
      expect(NotificationPayload.tryParse(data), isNull);
    });

    test('ids failing the shape check reject the whole payload', () {
      for (final bad in ['a/b', '', 'has space', 'x' * 201, '../etc', 'é']) {
        expect(
          NotificationPayload.tryParse(
            _customer('order_shipped', extra: {'orderId': bad}),
          ),
          isNull,
          reason: 'orderId=$bad',
        );
      }
      expect(
        NotificationPayload.tryParse(
          _customer('order_shipped', extra: {'orderId': 42}),
        ),
        isNull,
      );
      expect(
        NotificationPayload.tryParse({
          ..._customer('order_shipped'),
          'recipientUid': 'a/b',
        }),
        isNull,
      );
    });

    test('an admin payload ignores any recipientUid', () {
      final p = NotificationPayload.tryParse(
        _admin(
          'admin_new_order',
          extra: {'recipientUid': 'alice', 'orderId': 'o1'},
        ),
      );
      expect(p?.recipientUid, isNull);
      expect(p?.orderId, 'o1');
    });
  });

  group('NotificationType', () {
    test('fromWire maps known values and falls back to unknown', () {
      for (final t in NotificationType.values) {
        if (t == NotificationType.unknown) continue;
        expect(NotificationType.fromWire(t.wire), t);
      }
      expect(
        NotificationType.fromWire('brand_new_type'),
        NotificationType.unknown,
      );
      expect(NotificationType.fromWire(null), NotificationType.unknown);
      expect(NotificationType.fromWire('unknown'), NotificationType.unknown);
    });

    test('isOrder / isReview groupings', () {
      expect(NotificationType.orderDelivered.isOrder, isTrue);
      expect(NotificationType.paymentRefunded.isOrder, isFalse);
      expect(NotificationType.reviewHidden.isReview, isTrue);
      expect(NotificationType.orderPlaced.isReview, isFalse);
    });
  });

  group('AppNotification.fromFirestore', () {
    test('maps a full document', () {
      final n = AppNotification.fromFirestore('order_shipped_o1', {
        'type': 'order_shipped',
        'title': 'Order shipped',
        'body': 'Order #01234567 is on its way.',
        'route': 'orderDetail',
        'entityId': 'ord_1',
        'createdAt': Timestamp.fromDate(DateTime.utc(2026, 10, 2, 10)),
        'readAt': null,
      });
      expect(n.id, 'order_shipped_o1');
      expect(n.type, NotificationType.orderShipped);
      expect(n.route, 'orderDetail');
      expect(n.entityId, 'ord_1');
      expect(n.isUnread, isTrue);
      expect(n.createdAt.toUtc(), DateTime.utc(2026, 10, 2, 10));
    });

    test('a read row, and wrong-typed fields degrade safely (never throw)', () {
      final read = AppNotification.fromFirestore('x', {
        'type': 'order_placed',
        'readAt': Timestamp.fromDate(DateTime.utc(2026, 10, 3)),
      });
      expect(read.isUnread, isFalse);

      final junk = AppNotification.fromFirestore('y', {
        'type': 42,
        'title': 7,
        'body': null,
        'route': [],
        'entityId': 5,
        'createdAt': 'yesterday',
        'readAt': 'never',
      });
      expect(junk.type, NotificationType.unknown);
      expect(junk.title, '');
      expect(junk.body, '');
      expect(junk.route, '');
      expect(junk.entityId, isNull);
      expect(junk.isUnread, isTrue);
    });

    test('copyWith marks a row read', () {
      final n = AppNotification.fromFirestore('x', {'type': 'order_placed'});
      expect(n.copyWith(readAt: DateTime.now()).isUnread, isFalse);
    });
  });

  group('NotificationPrefs', () {
    test('missing doc / key / non-bool => ON; only explicit false is OFF', () {
      expect(NotificationPrefs.fromMap(null), const NotificationPrefs());
      expect(NotificationPrefs.fromMap({}), const NotificationPrefs());
      expect(
        NotificationPrefs.fromMap({'pushOrders': 'no', 'pushReviews': 0}),
        const NotificationPrefs(),
      );
      final off = NotificationPrefs.fromMap({
        'pushOrders': false,
        'pushAdminStock': false,
      });
      expect(off.pushOrders, isFalse);
      expect(off.pushReviews, isTrue);
      expect(off.pushAdminStock, isFalse);
      expect(off.pushAdminOrders, isTrue);
    });

    test(
      'toMap writes ONLY the role keys (a customer never sends pushAdmin*)',
      () {
        const p = NotificationPrefs(pushOrders: false);
        expect(p.toMap(isAdmin: false), {
          'pushOrders': false,
          'pushReviews': true,
        });
        expect(p.toMap(isAdmin: true).keys.toSet(), {
          'pushAdminOrders',
          'pushAdminStock',
          'pushAdminModeration',
          'pushAdminPayments',
        });
      },
    );

    test('equality and copyWith', () {
      const a = NotificationPrefs();
      expect(a.copyWith(pushOrders: false) == a, isFalse);
      expect(a.copyWith() == a, isTrue);
      expect(a.hashCode, const NotificationPrefs().hashCode);
    });
  });
}
