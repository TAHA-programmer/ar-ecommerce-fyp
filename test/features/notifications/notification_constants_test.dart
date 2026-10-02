import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/notifications/notification_constants.dart';

void main() {
  test('NotificationConstants.appVersion equals the pubspec.yaml version', () {
    final pubspec = File('pubspec.yaml').readAsStringSync();
    final match = RegExp(
      r'^version:\s*(\S+)\s*$',
      multiLine: true,
    ).firstMatch(pubspec);
    expect(match, isNotNull, reason: 'no version: line in pubspec.yaml');
    expect(NotificationConstants.appVersion, match!.group(1));
  });

  test('appVersion satisfies the server registerDevice validation', () {
    expect(NotificationConstants.appVersion.length, inInclusiveRange(1, 32));
    expect(
      NotificationConstants.appVersion,
      matches(RegExp(r'^[A-Za-z0-9_.+\- ]+$')),
    );
    expect(NotificationConstants.platform, 'android');
  });

  test('callable names match the deployed-function names in functions/src', () {
    final reg = File('functions/src/registerDevice.ts').readAsStringSync();
    final unreg = File('functions/src/unregisterDevice.ts').readAsStringSync();
    expect(
      reg,
      contains(
        'export const ${NotificationConstants.registerDeviceCallable} =',
      ),
    );
    expect(
      unreg,
      contains(
        'export const ${NotificationConstants.unregisterDeviceCallable} =',
      ),
    );
  });

  test('re-register interval is under the 60-day token TTL', () {
    expect(NotificationConstants.reRegisterAfter, const Duration(days: 7));
    expect(
      NotificationConstants.reRegisterAfter < const Duration(days: 60),
      isTrue,
    );
  });
}
