import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';

/// The contextual opt-in sheet (plan D14): shown only at a meaningful moment
/// (after the first order, the first Admin login, or from Settings) - never at
/// app launch. Pops `true` for "Turn on" and `false` for "Not now".
class NotificationPermissionSheet extends StatelessWidget {
  const NotificationPermissionSheet({super.key, required this.admin});

  final bool admin;

  @override
  Widget build(BuildContext context) {
    final title = admin ? 'Get store alerts' : 'Get order updates';
    final message = admin
        ? 'Turn on notifications to be alerted about new orders, low stock '
              'and flagged reviews. You can change this any time in '
              'Notification settings.'
        : "We'll only message you about your orders and account - for "
              'example when an order ships. You can turn this off any time '
              'in Notification settings.';

    // Scrollable: a modal bottom sheet is capped at 9/16 of the screen height,
    // so on a short/landscape phone (or large font scale) this content would
    // otherwise overflow.
    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: AppColors.primary.withValues(alpha: 0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.notifications_active_outlined,
                  color: AppColors.primaryDark,
                  size: 28,
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Text(
              title,
              textAlign: TextAlign.center,
              style: AppTypography.title,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            ElevatedButton(
              key: const Key('notification_permission_turn_on'),
              onPressed: () => Navigator.of(context).pop(true),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.textPrimary,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
                shape: const RoundedRectangleBorder(
                  borderRadius: AppRadii.mediumBorder,
                ),
              ),
              child: const Text('Turn on notifications'),
            ),
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              key: const Key('notification_permission_not_now'),
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(
                'Not now',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the sheet; `true` = turn on, anything else = not now.
Future<bool?> showNotificationPermissionSheet(
  BuildContext context, {
  required bool admin,
}) {
  return showModalBottomSheet<bool>(
    context: context,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: AppRadii.large),
    ),
    builder: (_) => NotificationPermissionSheet(admin: admin),
  );
}
