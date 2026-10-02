import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// What was last successfully registered with the server.
class RegisteredDevice {
  const RegisteredDevice({
    required this.uid,
    required this.token,
    required this.registeredAtMs,
  });

  final String uid;
  final String token;
  final int registeredAtMs;
}

/// On-device persistence for the notification data layer
/// (`SharedPreferences`, no secrets): a random per-install id, the last
/// successful registration, and whether the user declined the contextual
/// opt-in prompt (so it is never shown twice - plan D14).
///
/// The FCM token is a device identifier, not a credential, but it is only
/// ever sent to our own `registerDevice` callable and is never logged.
class DeviceRegistrationStore {
  static const _installIdKey = 'notif_install_id';
  static const _uidKey = 'notif_registered_uid';
  static const _tokenKey = 'notif_registered_token';
  static const _atKey = 'notif_registered_at_ms';
  static const _declinedKey = 'notif_prompt_declined';
  static const _declinedAdminKey = 'notif_prompt_declined_admin';

  /// Random 128-bit hex id generated once per install (not hardware-derived,
  /// not an advertising id). Server limit: 64 chars, `[A-Za-z0-9_.+\- ]`.
  Future<String> installId() async {
    final prefs = await SharedPreferences.getInstance();
    final existing = prefs.getString(_installIdKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final rng = Random.secure();
    final id = List.generate(
      16,
      (_) => rng.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    await prefs.setString(_installIdKey, id);
    return id;
  }

  Future<RegisteredDevice?> lastRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString(_uidKey);
    final token = prefs.getString(_tokenKey);
    final at = prefs.getInt(_atKey);
    if (uid == null || token == null || at == null) return null;
    return RegisteredDevice(uid: uid, token: token, registeredAtMs: at);
  }

  Future<void> saveRegistered(RegisteredDevice device) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_uidKey, device.uid);
    await prefs.setString(_tokenKey, device.token);
    await prefs.setInt(_atKey, device.registeredAtMs);
  }

  Future<void> clearRegistered() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_uidKey);
    await prefs.remove(_tokenKey);
    await prefs.remove(_atKey);
  }

  /// Whether the user already answered the contextual opt-in prompt with
  /// "Not now" / a denial. Tracked per audience so a customer's "Not now" never
  /// suppresses the one-time Admin explainer on a shared device (and vice
  /// versa).
  Future<bool> promptDeclined({bool admin = false}) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(admin ? _declinedAdminKey : _declinedKey) ?? false;
  }

  Future<void> setPromptDeclined(bool value, {bool admin = false}) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(admin ? _declinedAdminKey : _declinedKey, value);
  }
}
