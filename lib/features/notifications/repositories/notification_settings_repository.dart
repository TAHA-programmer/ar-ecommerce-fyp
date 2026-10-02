import '../models/notification_prefs.dart';

/// Reads/writes the signed-in user's push preferences
/// (`users/{uid}/notificationSettings/prefs`). Preferences gate the PUSH only
/// - the customer inbox always records every event (D7).
abstract class NotificationSettingsRepository {
  /// A missing doc (or key) yields the all-ON defaults. Throws only on a real
  /// read failure so the screen can show an honest error state.
  Future<NotificationPrefs> load(String uid);

  /// Persists the role's keys. Throws on failure so the screen can roll the
  /// switch back and say so.
  Future<void> save(
    String uid,
    NotificationPrefs prefs, {
    required bool isAdmin,
  });
}
