import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/app_notification.dart';
import '../models/notification_type.dart';

/// Short relative time for a row: "Just now", "5m", "3h", "Yesterday",
/// "Mar 4" (and "Mar 4, 2025" in another year). Pure for testing.
String relativeNotificationTime(DateTime when, DateTime now) {
  final diff = now.difference(when);
  if (diff.inMinutes < 1) return 'Just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m';
  if (diff.inHours < 24 && _sameDay(when, now)) return '${diff.inHours}h';
  if (_sameDay(when, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return when.year == now.year
      ? DateFormat('MMM d').format(when)
      : DateFormat('MMM d, yyyy').format(when);
}

/// Day-section label: "Today", "Yesterday" or a date. Pure for testing.
String notificationDayLabel(DateTime when, DateTime now) {
  if (_sameDay(when, now)) return 'Today';
  if (_sameDay(when, now.subtract(const Duration(days: 1)))) return 'Yesterday';
  return when.year == now.year
      ? DateFormat('MMMM d').format(when)
      : DateFormat('MMMM d, yyyy').format(when);
}

bool _sameDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

IconData _iconFor(NotificationType type) {
  switch (type) {
    case NotificationType.paymentRefunded:
      return Icons.account_balance_wallet_outlined;
    case NotificationType.reviewHidden:
    case NotificationType.reviewRejected:
    case NotificationType.reviewRestored:
      return Icons.rate_review_outlined;
    case NotificationType.orderDelivered:
      return Icons.inventory_2_outlined;
    case NotificationType.orderShipped:
      return Icons.local_shipping_outlined;
    case NotificationType.orderCancelled:
      return Icons.cancel_outlined;
    case NotificationType.orderPlaced:
    case NotificationType.orderConfirmed:
      return Icons.receipt_long_outlined;
    case NotificationType.unknown:
      return Icons.notifications_none;
  }
}

/// One Notification Centre row. Unread rows have a bold title and a lime
/// dot; tapping is handled by the parent (mark read + navigate).
class NotificationTile extends StatelessWidget {
  const NotificationTile({
    super.key,
    required this.notification,
    required this.now,
    required this.onTap,
  });

  final AppNotification notification;
  final DateTime now;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final unread = notification.isUnread;
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.largeBorder,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s),
        padding: const EdgeInsets.all(AppSpacing.s),
        decoration: BoxDecoration(
          color: unread
              ? AppColors.primary.withValues(alpha: 0.08)
              : AppColors.surface,
          borderRadius: AppRadii.largeBorder,
          border: Border.all(
            color: unread
                ? AppColors.primary.withValues(alpha: 0.5)
                : AppColors.neutralMediumLight,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.18),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _iconFor(notification.type),
                size: 20,
                color: AppColors.primaryDark,
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          notification.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Text(
                        relativeNotificationTime(notification.createdAt, now),
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    notification.body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
            if (unread) ...[
              const SizedBox(width: AppSpacing.xs),
              Container(
                key: const Key('notification_unread_dot'),
                margin: const EdgeInsets.only(top: 6),
                width: 10,
                height: 10,
                decoration: const BoxDecoration(
                  color: AppColors.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
