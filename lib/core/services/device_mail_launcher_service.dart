import 'package:url_launcher/url_launcher.dart';
import '../constants/app_contact.dart';
import 'mail_launcher_service.dart';

/// Real implementation of [MailLauncherService], wrapping
/// `package:url_launcher`'s `mailto:` support.
class DeviceMailLauncherService implements MailLauncherService {
  @override
  Future<bool> launchSupportEmail() async {
    final uri = Uri(
      scheme: 'mailto',
      path: AppContact.supportEmail,
      queryParameters: {'subject': AppContact.supportEmailSubject},
    );
    try {
      return await launchUrl(uri);
    } catch (_) {
      return false;
    }
  }
}
