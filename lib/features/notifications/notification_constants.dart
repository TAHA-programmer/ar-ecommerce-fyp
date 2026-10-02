/// Constants for the FCM notification data layer
/// (`26_FCM_NOTIFICATIONS_PLAN.md`, Stage S4).
class NotificationConstants {
  NotificationConstants._();

  /// Sent to `registerDevice` as `appVersion` (server limit: 32 chars,
  /// `[A-Za-z0-9_.+\- ]`). MUST equal the `version:` line in `pubspec.yaml`
  /// - `test/features/notifications/notification_constants_test.dart` fails
  /// if they drift (no `package_info_plus` dependency is added just for this).
  static const String appVersion = '1.0.0+1';

  /// Android is the only supported platform (the server rejects anything
  /// else).
  static const String platform = 'android';

  /// Callable names (region `us-central1`, same as the checkout callable -
  /// `StripeConfig.functionsRegion`).
  static const String registerDeviceCallable = 'registerDevice';
  static const String unregisterDeviceCallable = 'unregisterDevice';

  /// The token doc has a 60-day server-side TTL; re-registering weekly keeps
  /// `lastSeenAt`/`expireAt` fresh without writing on every app start.
  static const Duration reRegisterAfter = Duration(days: 7);

  /// Logout must never hang: server unregister and local token deletion are
  /// each best-effort and time-boxed.
  static const Duration unregisterTimeout = Duration(seconds: 5);
  static const Duration registerTimeout = Duration(seconds: 15);
}
