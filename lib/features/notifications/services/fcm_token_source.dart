/// Seam over the `FirebaseMessaging` token APIs. Never throws: failures
/// resolve to `null` / complete normally (FCM can legitimately be
/// unavailable, e.g. no Google Play services or no network).
abstract class FcmTokenSource {
  /// The current device FCM token, or `null` if unavailable.
  Future<String?> getToken();

  /// Invalidates the current token (a fresh one is minted on the next
  /// [getToken]). Called on logout so the previous user can never receive
  /// pushes on this device.
  Future<void> deleteToken();

  /// Emits whenever FCM rotates the token.
  Stream<String> get onTokenRefresh;
}
