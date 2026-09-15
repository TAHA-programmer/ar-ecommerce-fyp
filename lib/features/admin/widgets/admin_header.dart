import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/constants/app_assets.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/core/theme/app_spacing.dart';
import '../notifications/admin_notification_signal.dart';
import 'admin_account_sheet.dart';

class AdminHeader extends StatelessWidget implements PreferredSizeWidget {
  final String title;
  final bool showGreeting;
  final VoidCallback? onBack;

  const AdminHeader({
    super.key,
    required this.title,
    this.showGreeting = false,
    this.onBack,
  });

  @override
  Size get preferredSize => Size.fromHeight(showGreeting ? 120.0 : 80.0);

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthSessionState>();
    final notificationCount = adminNotificationCount(
      context.watch<CommerceDatabase>(),
    );
    final String displayName;
    if (authState.isSuperAdmin) {
      displayName = 'Super Admin';
    } else {
      final email = authState.email ?? 'admin@twinar.com';
      final namePrefix = email.split('@').first;
      // Capitalize first letter
      displayName = namePrefix.isNotEmpty
          ? '${namePrefix[0].toUpperCase()}${namePrefix.substring(1)}'
          : 'Admin';
    }

    return Container(
      color: AppColors.surface,
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + AppSpacing.s,
        left: AppSpacing.m,
        right: AppSpacing.m,
        bottom: AppSpacing.s,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Logo and Admin Text
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  if (onBack != null) ...[
                    IconButton(
                      key: const Key('admin_header_back_button'),
                      onPressed: onBack,
                      icon: const Icon(Icons.arrow_back),
                      tooltip: 'Back to Product Management',
                    ),
                    const SizedBox(width: AppSpacing.xxs),
                  ],
                  Image.asset(
                    AppAssets.headerLogo,
                    height: 32,
                    fit: BoxFit.contain,
                  ),
                ],
              ),
              // Action Icons
              Row(
                children: [
                  Stack(
                    alignment: Alignment.center,
                    clipBehavior: Clip.none,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.notifications_none,
                          color: AppColors.black,
                        ),
                        tooltip: notificationCount > 0
                            ? 'Notifications, $notificationCount pending'
                            : 'Notifications',
                        onPressed: () => Navigator.of(
                          context,
                        ).pushNamed(RouteNames.adminNotifications),
                      ),
                      // Same numeric-pill convention as the customer cart
                      // badge (`CustomerHeader`) - a growing pill sized by
                      // its own text, not a fixed dot, so it stays legible
                      // for any count without a "99+" cap.
                      if (notificationCount > 0)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            key: const Key('admin_notification_badge'),
                            padding: const EdgeInsets.all(4),
                            decoration: const BoxDecoration(
                              color: AppColors.primary,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                              minWidth: 16,
                              minHeight: 16,
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              '$notificationCount',
                              style: const TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  GestureDetector(
                    onTap: () {
                      showModalBottomSheet(
                        context: context,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(16),
                          ),
                        ),
                        builder: (context) => const AdminAccountSheet(),
                      );
                    },
                    child: CircleAvatar(
                      backgroundColor: AppColors.primaryLight.withValues(
                        alpha: 0.3,
                      ),
                      radius: 18,
                      child: const Icon(
                        Icons.person,
                        color: AppColors.primary,
                        size: 20,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
          if (showGreeting) ...[
            const SizedBox(height: AppSpacing.s),
            Text(
              'Hello, $displayName 👋',
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
