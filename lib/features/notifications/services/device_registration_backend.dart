/// Seam over the `registerDevice` / `unregisterDevice` callables. The server
/// stamps the role from the verified ID token - the client never sends one.
abstract class DeviceRegistrationBackend {
  /// Returns `true` on success. Never throws.
  Future<bool> register({
    required String token,
    required String installId,
    required String appVersion,
  });

  /// Returns `true` when the call completed (whether or not a doc was
  /// removed). Never throws.
  Future<bool> unregister({required String token});
}
