import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes/route_names.dart';
import '../../../app/viewmodels/auth_session_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../../notifications/services/notification_lifecycle.dart';
import '../repositories/auth_repository.dart';

/// The one sign-out sequence shared by the customer Profile and the Admin
/// account sheet, run AFTER the user has confirmed the "Log Out?" dialog.
///
/// Sign-out can take several seconds on a slow network (the FCM unregister is
/// time-boxed to 5 s and the local token delete to another 5 s, then the
/// Firebase + Google sign-out). Until now nothing covered the screen during
/// that window, so the app looked usable and Logout could be tapped again. This
/// puts a non-dismissible "Signing out…" overlay over the whole route stack and
/// refuses a second run while one is in flight.
///
/// The secure order is unchanged: FCM cleanup while still authenticated ->
/// Firebase/Google sign-out -> clear the session -> replace the stack with
/// Login. `beforeSignOut` never throws and is time-boxed; the sign-out calls
/// are not, so a thrown error is caught, the overlay is removed and the user
/// is told to retry (the session is left intact).
class LogoutFlow {
  LogoutFlow._();

  static bool _inFlight = false;

  /// True while a sign-out is running. Exposed for tests and callers that
  /// want to ignore a second request.
  static bool get isInFlight => _inFlight;

  @visibleForTesting
  static void resetForTest() => _inFlight = false;

  static Future<void> run(BuildContext context) async {
    if (_inFlight) return;
    _inFlight = true;

    final navigator = Navigator.of(context);
    final authRepo = context.read<AuthRepository>();
    final authState = context.read<AuthSessionState>();
    final lifecycle = context.read<NotificationLifecycle?>();

    // A route object we own, pushed onto the same navigator (not the root
    // one): the final pushNamedAndRemoveUntil below removes it together with
    // everything else, and a failure can remove exactly this route even if it
    // has not been built yet (a synchronous throw never races the first frame).
    final overlayRoute = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SigningOutOverlay(),
    );
    unawaited(navigator.push(overlayRoute));

    try {
      // FCM: remove this device's token while still authenticated, so the
      // previous user can never receive pushes on this phone (best-effort,
      // time-boxed, never blocks or fails the logout).
      await lifecycle?.beforeSignOut();
      await authRepo.signOut();
      authState.clearSession();

      if (navigator.mounted) {
        navigator.pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
      }
    } catch (e) {
      debugPrint('LogoutFlow failed: ${e.runtimeType}');
      if (navigator.mounted && overlayRoute.isActive) {
        navigator.removeRoute(overlayRoute);
      }
      if (context.mounted) {
        AppToast.error(context, 'Could not log out. Please try again.');
      }
    } finally {
      _inFlight = false;
    }
  }
}

class _SigningOutOverlay extends StatelessWidget {
  const _SigningOutOverlay();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Center(
        child: Material(
          color: AppColors.white,
          borderRadius: AppRadii.mediumBorder,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.xl,
              vertical: AppSpacing.l,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const SizedBox(
                  width: 28,
                  height: 28,
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    color: AppColors.primary,
                  ),
                ),
                const SizedBox(height: AppSpacing.m),
                Text('Signing out…', style: AppTypography.bodyMedium),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
