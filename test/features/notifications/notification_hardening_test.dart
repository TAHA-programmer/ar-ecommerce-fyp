import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/app.dart';

/// Stage S6 final-hardening guards (26_FCM_NOTIFICATIONS_PLAN.md): decisions
/// that must not silently regress. Static checks over the source tree - the
/// properties are about what is NOT in the app.
void main() {
  String read(String path) => File(path).readAsStringSync();

  Iterable<File> dartFiles(String dir) => Directory(dir)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'));

  test('D12: no flutter_local_notifications dependency', () {
    expect(
      read('pubspec.yaml'),
      isNot(
        contains(RegExp(r'^\s+flutter_local_notifications:', multiLine: true)),
      ),
    );
    expect(
      read('pubspec.lock'),
      isNot(contains('flutter_local_notifications')),
    );
  });

  test('no onBackgroundMessage handler is registered anywhere in the app', () {
    for (final f in dartFiles('lib')) {
      final code = f
          .readAsLinesSync()
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      expect(code, isNot(contains('onBackgroundMessage')), reason: f.path);
    }
  });

  test('no FCM server key / service-account material ships in the app', () {
    final patterns = [
      RegExp(r'AAAA[A-Za-z0-9_-]{20,}'),
      RegExp('private_key'),
      RegExp('BEGIN PRIVATE KEY'),
      RegExp(r'fcm\.googleapis\.com/fcm/send'), // the retired legacy HTTP API
    ];
    for (final f in dartFiles('lib')) {
      final text = f.readAsStringSync();
      for (final p in patterns) {
        expect(p.hasMatch(text), isFalse, reason: '${f.path} matches $p');
      }
    }
  });

  test(
    'the app never logs a token, uid or message payload (only exception types)',
    () {
      for (final f in dartFiles('lib/features/notifications')) {
        for (final line in f.readAsLinesSync().where(
          (l) => l.contains('debugPrint(') || l.contains(' print('),
        )) {
          // the only allowed form is debugPrint('...: ${e.runtimeType}')
          expect(
            line.contains(r'${e.runtimeType}'),
            isTrue,
            reason: '${f.path}: $line',
          );
          expect(line.contains(r'$token'), isFalse, reason: '${f.path}: $line');
          expect(
            line.contains('message.data'),
            isFalse,
            reason: '${f.path}: $line',
          );
        }
      }
    },
  );

  test(
    'the notification lifecycle is OFF by default and production main.dart turns it on',
    () {
      expect(const TWinArApp().enableNotifications, isFalse);
      expect(read('lib/main.dart'), contains('enableNotifications: true'));
    },
  );

  test(
    'the Admin Notifications screen and its state-derived badge are untouched (D2/D8)',
    () {
      final signal = read(
        'lib/features/admin/notifications/admin_notification_signal.dart',
      );
      expect(
        signal,
        contains('int adminNotificationCount(CommerceDatabase db)'),
      );
      expect(signal, contains('p.stockQuantity > 0'));
      final vm = read(
        'lib/features/admin/notifications/viewmodels/admin_notifications_viewmodel.dart',
      );
      expect(vm, contains('lowStockProducts'));
      expect(vm, contains('pendingOrders'));
      // no read/unread or persisted inbox was bolted onto the Admin surface
      for (final f in dartFiles('lib/features/admin/notifications')) {
        final t = f.readAsStringSync();
        expect(
          t,
          isNot(contains('NotificationInboxRepository')),
          reason: f.path,
        );
        expect(t, isNot(contains('readAt')), reason: f.path);
      }
    },
  );

  test(
    'client never sends admin-only preference keys for a customer and never writes an inbox row',
    () {
      final repo = read(
        'lib/features/notifications/repositories/firestore_notification_inbox_repository.dart',
      );
      expect(repo, isNot(contains('.add(')));
      expect(repo, isNot(contains('.set(')));
      // only readAt is ever updated
      final updates = RegExp(
        r"update\(\{\s*'([A-Za-z]+)'",
      ).allMatches(repo).map((m) => m.group(1)).toSet();
      expect(updates, {'readAt'});
    },
  );

  test(
    'server: kill-switch defaults OFF and device tokens are never client-readable',
    () {
      final cfg = read('functions/src/config.ts');
      expect(cfg, contains('defineBoolean("NOTIFICATIONS_ENABLED"'));
      expect(
        RegExp(
          r'NOTIFICATIONS_ENABLED"[\s\S]{0,80}default: false',
        ).hasMatch(cfg),
        isTrue,
      );
      final rules = read('firestore.rules');
      expect(
        RegExp(
          r'match /deviceTokens/\{tokenHash\} \{\s*allow read, write: if false;',
        ).hasMatch(rules),
        isTrue,
      );
      expect(
        RegExp(
          r'match /notificationEvents/\{eventKey\} \{\s*allow read, write: if false;',
        ).hasMatch(rules),
        isTrue,
      );
    },
  );
}
