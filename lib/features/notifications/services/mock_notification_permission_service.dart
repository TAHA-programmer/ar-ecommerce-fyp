import 'notification_permission_service.dart';

/// Test double for [NotificationPermissionService]. No platform channel.
class MockNotificationPermissionService
    implements NotificationPermissionService {
  MockNotificationPermissionService({
    this.current = NotificationPermissionStatus.granted,
    this.afterRequest,
  });

  NotificationPermissionStatus current;

  /// What [request] resolves to (defaults to leaving [current] unchanged).
  NotificationPermissionStatus? afterRequest;

  int requestCount = 0;
  int openSettingsCount = 0;

  @override
  Future<NotificationPermissionStatus> status() async => current;

  @override
  Future<NotificationPermissionStatus> request() async {
    requestCount++;
    current = afterRequest ?? current;
    return current;
  }

  @override
  Future<bool> openSettings() async {
    openSettingsCount++;
    return true;
  }
}
