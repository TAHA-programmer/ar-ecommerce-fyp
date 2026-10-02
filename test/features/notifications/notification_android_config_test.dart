import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Cross-layer drift guards for the Android side of FCM (Stage S4): the
/// manifest, the native channel creation, the status-bar icon and the
/// server's channel ids must all agree - none of this can be unit-tested
/// through a platform channel, so the files themselves are the contract.
void main() {
  final manifest = File(
    'android/app/src/main/AndroidManifest.xml',
  ).readAsStringSync();
  final kotlin = File(
    'android/app/src/main/kotlin/com/tahafayyaz/twin_ar/NotificationChannels.kt',
  ).readAsStringSync();
  final mainActivity = File(
    'android/app/src/main/kotlin/com/tahafayyaz/twin_ar/MainActivity.kt',
  ).readAsStringSync();
  final serverConstants = File(
    'functions/src/lib/notifications/constants.ts',
  ).readAsStringSync();

  String serverChannel(String name) {
    final m = RegExp(
      'export const $name = "([a-z_]+)";',
    ).firstMatch(serverConstants);
    expect(m, isNotNull, reason: '$name missing from server constants');
    return m!.group(1)!;
  }

  test('manifest declares the Android 13+ POST_NOTIFICATIONS permission', () {
    expect(
      manifest,
      contains(
        '<uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>',
      ),
    );
  });

  test('manifest declares FCM default channel, icon and colour', () {
    expect(
      manifest,
      contains('com.google.firebase.messaging.default_notification_channel_id'),
    );
    expect(manifest, contains('android:value="orders"'));
    expect(manifest, contains('@drawable/ic_stat_twin_ar'));
    expect(manifest, contains('@color/notification_accent'));
  });

  test('the four Kotlin channel ids equal the server CHANNEL_* constants', () {
    final server = {
      'ORDERS': serverChannel('CHANNEL_ORDERS'),
      'ACCOUNT': serverChannel('CHANNEL_ACCOUNT'),
      'ADMIN_OPS': serverChannel('CHANNEL_ADMIN_OPS'),
      'ADMIN_STOCK': serverChannel('CHANNEL_ADMIN_STOCK'),
    };
    server.forEach((constName, id) {
      expect(
        kotlin,
        contains('const val $constName = "$id"'),
        reason: 'Kotlin $constName must be "$id" (server constant)',
      );
    });
    // the manifest default channel must be one of them
    expect(server.values, contains('orders'));
  });

  test(
    'D6: account channel is low importance; order/admin-ops channels are high',
    () {
      expect(
        RegExp(r'ACCOUNT,[\s\S]*?IMPORTANCE_LOW').hasMatch(kotlin),
        isTrue,
      );
      expect(
        RegExp(r'ORDERS,[\s\S]*?IMPORTANCE_HIGH').hasMatch(kotlin),
        isTrue,
      );
      expect(
        RegExp(r'ADMIN_OPS,[\s\S]*?IMPORTANCE_HIGH').hasMatch(kotlin),
        isTrue,
      );
    },
  );

  test('channels are created at app start and need no permission', () {
    expect(mainActivity, contains('NotificationChannels.ensureCreated('));
    expect(kotlin, contains('createNotificationChannels'));
  });

  test(
    'status-bar icon is a white-only vector on transparent (no grey-square risk)',
    () {
      final icon = File(
        'android/app/src/main/res/drawable/ic_stat_twin_ar.xml',
      ).readAsStringSync();
      expect(icon, contains('<vector'));
      final fills = RegExp(
        r'android:fillColor="(#[0-9A-Fa-f]+)"',
      ).allMatches(icon).map((m) => m.group(1)!.toUpperCase()).toSet();
      expect(fills, {'#FFFFFFFF'});
      expect(icon, isNot(contains('android:tint')));
    },
  );

  test('notification accent equals AppColors.primary lime', () {
    final colors = File(
      'android/app/src/main/res/values/colors.xml',
    ).readAsStringSync();
    final app = File('lib/core/theme/app_colors.dart').readAsStringSync();
    expect(colors, contains('name="notification_accent">#AEC500<'));
    expect(app, contains('primary = Color(0xFFAEC500)'));
  });
}
