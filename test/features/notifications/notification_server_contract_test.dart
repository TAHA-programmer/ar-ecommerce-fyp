import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/notifications/models/notification_payload.dart';
import 'package:twin_ar/features/notifications/models/notification_prefs.dart';
import 'package:twin_ar/features/notifications/models/notification_type.dart';

/// Drift guards between the Flutter notification layer and the server
/// (functions/src/lib/notifications) + `firestore.rules`: the contract is
/// strings on both sides, so the source files themselves are compared.
void main() {
  final types = File(
    'functions/src/lib/notifications/types.ts',
  ).readAsStringSync();
  final constants = File(
    'functions/src/lib/notifications/constants.ts',
  ).readAsStringSync();
  final catalog = File(
    'functions/src/lib/notifications/catalog.ts',
  ).readAsStringSync();
  final prefsTs = File(
    'functions/src/lib/notifications/prefs.ts',
  ).readAsStringSync();
  final rules = File('firestore.rules').readAsStringSync();

  Set<String> tsList(String constName) {
    final m = RegExp(
      '$constName = \\[([\\s\\S]*?)\\] as const',
    ).firstMatch(types);
    expect(m, isNotNull, reason: '$constName not found');
    return RegExp(
      r'"([a-z_]+)"',
    ).allMatches(m!.group(1)!).map((x) => x.group(1)!).toSet();
  }

  test('customer notification types: server list == app inbox type enum', () {
    final server = tsList('CUSTOMER_NOTIFICATION_TYPES');
    final app = NotificationType.values
        .where((t) => t != NotificationType.unknown)
        .map((t) => t.wire)
        .toSet();
    expect(app, server);
  });

  test(
    'push payload types: server customer + admin lists == app payload enum',
    () {
      final server = {
        ...tsList('CUSTOMER_NOTIFICATION_TYPES'),
        ...tsList('ADMIN_NOTIFICATION_TYPES'),
      };
      final app = NotificationPayloadType.values.map((t) => t.wire).toSet();
      expect(app, server);
    },
  );

  test('admin-ness: app treats exactly the server admin types as admin', () {
    final serverAdmin = tsList('ADMIN_NOTIFICATION_TYPES');
    final appAdmin = NotificationPayloadType.values
        .where((t) => t.isAdmin)
        .map((t) => t.wire)
        .toSet();
    expect(appAdmin, serverAdmin);
  });

  test('payload schema version matches the server PAYLOAD_VERSION', () {
    final m = RegExp(r'PAYLOAD_VERSION = "(\d+)"').firstMatch(constants);
    expect(m, isNotNull);
    expect(NotificationPayload.supportedVersion, m!.group(1));
  });

  test('inbox destination enums the app understands exist on the server', () {
    // the three routes resolveInboxRow supports must be real server ClientRoute values
    for (final route in ['orderDetail', 'orders', 'myReviews']) {
      expect(types, contains('"$route"'), reason: route);
      expect(catalog, contains('route: "$route"'), reason: route);
    }
  });

  test(
    'every push pref key the app writes is a key the server reads AND the rules allow',
    () {
      final appKeys = {
        ...const NotificationPrefs().toMap(isAdmin: false).keys,
        ...const NotificationPrefs().toMap(isAdmin: true).keys,
      };
      for (final key in appKeys) {
        expect(
          prefsTs,
          contains('"$key"'),
          reason: 'server prefs.ts missing $key',
        );
        expect(
          rules,
          contains("'$key'"),
          reason: 'firestore.rules missing $key',
        );
      }
      expect(appKeys, hasLength(6));
    },
  );

  test(
    'the notification payload parser accepts exactly what the server buildPushData emits',
    () {
      // server shape (payload.ts): v, type, audience, [recipientUid], [entity id], [notificationId]
      final customer = NotificationPayload.tryParse({
        'v': '1',
        'type': 'order_confirmed',
        'audience': 'customer',
        'recipientUid': 'uid1',
        'orderId': 'ord_0123456789abcdef0123456789abcdef01234567',
        'notificationId':
            'order_confirmed_ord_0123456789abcdef0123456789abcdef01234567',
      });
      expect(customer, isNotNull);
      final admin = NotificationPayload.tryParse({
        'v': '1',
        'type': 'admin_low_stock',
        'audience': 'admin',
        'productId': 'luna-accent-chair',
      });
      expect(admin, isNotNull);
      // review ids are `{uid}_{productId}` and refund ids contain `pi_` - both must pass the id check
      expect(
        NotificationPayload.tryParse({
          'v': '1',
          'type': 'review_hidden',
          'audience': 'customer',
          'recipientUid': 'uid1',
          'reviewId': 'uid1_luna-accent-chair',
          'notificationId':
              'review_hidden_uid1_luna-accent-chair_1700000000000',
        }),
        isNotNull,
      );
      expect(
        NotificationPayload.tryParse({
          'v': '1',
          'type': 'payment_refunded',
          'audience': 'customer',
          'recipientUid': 'uid1',
          'notificationId': 'refund_pi_3Abc123',
        }),
        isNotNull,
      );
    },
  );
}
