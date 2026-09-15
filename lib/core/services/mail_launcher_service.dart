/// Opens the device's email app to compose a message to TWin AR support.
///
/// This only prepares and hands off a `mailto:` compose intent - it never
/// sends anything itself and never touches the network. Whether the
/// recipient address in [AppContact.supportEmail] actually has a monitored
/// mailbox behind it is a deployment/ownership concern, entirely separate
/// from this seam working correctly.
abstract class MailLauncherService {
  /// Returns `true` once a compose intent was successfully handed to an
  /// email app, `false` if no app could handle it or the OS refused the
  /// request (e.g. no email client installed). Never throws.
  Future<bool> launchSupportEmail();
}
