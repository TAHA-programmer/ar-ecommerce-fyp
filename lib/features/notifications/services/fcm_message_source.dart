/// A push message as the app needs it: the data payload plus the
/// notification text (shown by the in-app banner while foregrounded).
class IncomingPushMessage {
  const IncomingPushMessage({required this.data, this.title, this.body});

  final Map<String, dynamic> data;
  final String? title;
  final String? body;
}

/// Seam over the `FirebaseMessaging` message streams so the lifecycle is
/// testable without a platform channel. Never throws.
abstract class FcmMessageSource {
  /// The message that cold-started the app from a tapped notification, if any
  /// (delivered once).
  Future<IncomingPushMessage?> initialMessage();

  /// A notification tapped while the app was in the background.
  Stream<IncomingPushMessage> get onMessageOpenedApp;

  /// A message that arrived while the app is in the foreground (the OS shows
  /// no system notification in that case - the app shows its own banner).
  Stream<IncomingPushMessage> get onForegroundMessage;
}
