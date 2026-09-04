import 'package:shared_preferences/shared_preferences.dart';

/// Persists (or clears) the email address associated with the Login
/// screen's "Remember Me" checkbox, on-device only. Never stores a
/// password.
class RememberedLoginStore {
  static const _emailKey = 'remembered_login_email';

  Future<String?> getSavedEmail() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_emailKey);
  }

  Future<void> saveEmail(String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_emailKey, email);
  }

  Future<void> clearEmail() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_emailKey);
  }
}
