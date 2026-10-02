import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../services/notification_permission_service.dart';

/// "Notifications are off" strip shown at the top of the Notification Centre
/// and Settings when the OS permission isn't granted. Honest, never nagging:
/// the inbox keeps working regardless, and the banner can be dismissed for the
/// session.
class NotificationPermissionBanner extends StatelessWidget {
  const NotificationPermissionBanner({
    super.key,
    required this.status,
    required this.onTurnOn,
    required this.onDismiss,
  });

  final NotificationPermissionStatus status;
  final VoidCallback onTurnOn;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final blocked = status == NotificationPermissionStatus.blocked;
    return Container(
      key: const Key('notification_permission_banner'),
      margin: const EdgeInsets.only(bottom: AppSpacing.s),
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.10),
        borderRadius: AppRadii.largeBorder,
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.notifications_off_outlined,
            color: AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              "Notifications are off - you'll still see updates here.",
              style: AppTypography.bodySmall,
            ),
          ),
          TextButton(
            key: const Key('notification_permission_banner_action'),
            onPressed: onTurnOn,
            child: Text(
              blocked ? 'Open settings' : 'Turn on',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          IconButton(
            key: const Key('notification_permission_banner_dismiss'),
            visualDensity: VisualDensity.compact,
            onPressed: onDismiss,
            icon: const Icon(Icons.close, size: 18),
          ),
        ],
      ),
    );
  }
}
