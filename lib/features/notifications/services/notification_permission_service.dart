/// OS notification-permission state (Android 13+ `POST_NOTIFICATIONS`).
///
/// Android 12 and below have no runtime permission, so they report
/// [granted] unless the user disabled notifications for the app in system
/// settings (then [blocked]).
enum NotificationPermissionStatus {
  /// Notifications may be shown.
  granted,

  /// Not granted; the system dialog may still be shown (never asked, or
  /// declined once on Android 13+).
  denied,

  /// Not granted and the system will no longer show the dialog (declined
  /// twice, or disabled in system settings). Only "Open settings" can fix it.
  blocked,
}

/// Seam over the OS notification permission so services and view-models are
/// testable without a platform channel. Never throws.
abstract class NotificationPermissionService {
  Future<NotificationPermissionStatus> status();

  /// Shows the system permission dialog when the OS allows it, then returns
  /// the resulting status. Callers MUST only invoke this from a contextual
  /// opt-in moment (plan D14) - never at app launch.
  Future<NotificationPermissionStatus> request();

  /// Opens the app's system settings page. Returns whether it was opened.
  Future<bool> openSettings();
}
