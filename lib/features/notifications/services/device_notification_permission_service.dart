import 'package:permission_handler/permission_handler.dart';

import 'notification_permission_service.dart';

/// Real [NotificationPermissionService] on `permission_handler` (already a
/// dependency for the Room AR camera permission). `Permission.notification`
/// maps to `POST_NOTIFICATIONS` on Android 13+ and is always granted below.
class DeviceNotificationPermissionService
    implements NotificationPermissionService {
  @override
  Future<NotificationPermissionStatus> status() async {
    try {
      return _map(await Permission.notification.status);
    } catch (_) {
      return NotificationPermissionStatus.denied;
    }
  }

  @override
  Future<NotificationPermissionStatus> request() async {
    try {
      return _map(await Permission.notification.request());
    } catch (_) {
      return NotificationPermissionStatus.denied;
    }
  }

  @override
  Future<bool> openSettings() async {
    try {
      return await openAppSettings();
    } catch (_) {
      return false;
    }
  }

  NotificationPermissionStatus _map(PermissionStatus status) {
    if (status.isGranted || status.isLimited || status.isProvisional) {
      return NotificationPermissionStatus.granted;
    }
    if (status.isPermanentlyDenied || status.isRestricted) {
      return NotificationPermissionStatus.blocked;
    }
    return NotificationPermissionStatus.denied;
  }
}
