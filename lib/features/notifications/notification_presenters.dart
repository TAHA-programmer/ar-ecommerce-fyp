import 'package:flutter/material.dart';

import '../../app/routes/app_router.dart';
import '../../core/widgets/feedback/app_toast.dart';
import 'widgets/notification_permission_sheet.dart';

/// The BuildContext used for notification UI that is triggered outside any
/// screen (a foreground push, the Admin explainer): the root Navigator's
/// OVERLAY context - it sits under the Navigator (so `Navigator.of`,
/// `Overlay.of`, `Theme` and `MediaQuery` all resolve), unlike the
/// Navigator's own `currentContext`.
BuildContext? _overlayContext() =>
    AppRouter.navigatorKey.currentState?.overlay?.context;

/// Production `OptInPresenter`: the contextual permission sheet.
Future<bool?> presentOptInSheet({required bool admin}) async {
  final context = _overlayContext();
  if (context == null) return null;
  return showNotificationPermissionSheet(context, admin: admin);
}

/// Production `BannerPresenter`: the tappable in-app push banner.
///
/// Inserts straight into the root Navigator's [OverlayState]. It must NOT go
/// through `Overlay.of(overlay.context)`: that context IS the Overlay, so the
/// ancestor lookup finds nothing and throws "No Overlay widget found" inside
/// the FCM stream listener - the banner silently never appeared (found in the
/// S8 foreground retest).
void presentPushBanner({
  required String title,
  required String body,
  required VoidCallback onTap,
}) {
  final overlay = AppRouter.navigatorKey.currentState?.overlay;
  if (overlay == null) return;
  AppToast.notification(
    null,
    overlay: overlay,
    title: title,
    message: body,
    onTap: onTap,
  );
}
