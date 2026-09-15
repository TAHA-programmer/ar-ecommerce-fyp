/// Centralized support-contact details, so the address is defined exactly
/// once and every surface that shows or emails it (Help & Support today;
/// anywhere else in the future) stays in sync automatically.
///
/// [supportEmail] is a real, developer-owned mailbox (confirmed
/// 2026-09-16 — see `25_PROFILE_SUPPORT_AND_ADMIN_AUDIT.md` §2). Update
/// this single constant if the mailbox ever changes; nothing else in the
/// app needs to change.
class AppContact {
  AppContact._();

  static const String supportEmail = 'twinar.support@gmail.com';

  static const String supportEmailSubject = 'TWin AR Support Request';
}
