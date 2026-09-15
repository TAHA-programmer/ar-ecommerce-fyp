import 'mail_launcher_service.dart';

/// Test double for [MailLauncherService]. Records every call and returns
/// [result] (default `true`) without touching any platform channel.
class MockMailLauncherService implements MailLauncherService {
  MockMailLauncherService({this.result = true});

  final bool result;
  int callCount = 0;

  @override
  Future<bool> launchSupportEmail() async {
    callCount++;
    return result;
  }
}
