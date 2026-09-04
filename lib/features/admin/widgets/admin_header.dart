import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/constants/app_assets.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/core/theme/app_spacing.dart';
import 'admin_notification_sheet.dart';
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
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.notifications_none,
                          color: AppColors.black,
                        ),
                        onPressed: () {
                          showModalBottomSheet(
                            context: context,
                            shape: const RoundedRectangleBorder(
                              borderRadius: BorderRadius.vertical(
                                top: Radius.circular(16),
                              ),
                            ),
                            builder: (context) =>
                                const AdminNotificationSheet(),
                          );
                        },
                      ),
                      Positioned(
                        right: 12,
                        top: 12,
                        child: Container(
                          width: 8,
                          height: 8,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
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
