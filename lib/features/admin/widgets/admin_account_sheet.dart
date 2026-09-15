import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_radii.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/core/theme/app_spacing.dart';

class AdminAccountSheet extends StatelessWidget {
  const AdminAccountSheet({super.key});

  /// Mirrors the customer Profile's own logout confirmation
  /// (`ProfileView._confirmLogout`) so both surfaces ask the same question
  /// before signing out. The `Navigator` is captured before the sheet is
  /// popped so the post-sign-out redirect to Login still has somewhere
  /// valid to push to, even though this widget's own `context` is gone by
  /// then.
  Future<void> _confirmLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mediumBorder,
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        title: Text('Log Out?', style: AppTypography.title),
        content: Text(
          'Are you sure you want to log out?',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final navigator = Navigator.of(context);
    final authRepo = context.read<AuthRepository>();
    final authState = context.read<AuthSessionState>();

    navigator.pop(); // close the account sheet

    await authRepo.signOut();
    authState.clearSession();

    navigator.pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
  }

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthSessionState>();
    final email = authState.email ?? 'admin@twinar.com';

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: AppColors.primaryLight.withValues(
                    alpha: 0.3,
                  ),
                  radius: 24,
                  child: const Icon(
                    Icons.person,
                    color: AppColors.primary,
                    size: 28,
                  ),
                ),
                const SizedBox(width: AppSpacing.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Super Admin',
                        style: AppTypography.title.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        email,
                        style: AppTypography.bodyMedium.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Role: Super Admin',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.primaryDark,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xl),
            const Divider(),
            const SizedBox(height: AppSpacing.s),
            ListTile(
              key: const Key('admin_account_sheet_reviews_tile'),
              leading: const Icon(Icons.rate_review_outlined),
              title: Text('Reviews Moderation', style: AppTypography.bodyLarge),
              onTap: () {
                Navigator.of(context).pop();
                Navigator.of(context).pushNamed(RouteNames.adminReviews);
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.neutralMedium),
              title: Text(
                'Log Out',
                style: AppTypography.bodyLarge.copyWith(color: AppColors.error),
              ),
              onTap: () => _confirmLogout(context),
            ),
          ],
        ),
      ),
    );
  }
}
