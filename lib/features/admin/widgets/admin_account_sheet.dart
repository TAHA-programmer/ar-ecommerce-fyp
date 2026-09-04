import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/core/theme/app_spacing.dart';

class AdminAccountSheet extends StatelessWidget {
  const AdminAccountSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final authState = context.watch<AuthSessionState>();
    final email = authState.email ?? 'admin@twinar.com';

    return SafeArea(
      child: Padding(
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
              leading: const Icon(Icons.settings_outlined),
              title: Text('Account Settings', style: AppTypography.bodyLarge),
              onTap: () {
                // Not implemented in this phase
                Navigator.of(context).pop();
              },
            ),
            ListTile(
              leading: const Icon(Icons.logout, color: AppColors.neutralMedium),
              title: Text(
                'Log Out',
                style: AppTypography.bodyLarge.copyWith(color: AppColors.error),
              ),
              subtitle: Text(
                'Mock Logout for testing',
                style: AppTypography.caption.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              onTap: () async {
                final authRepo = context.read<AuthRepository>();
                final authState = context.read<AuthSessionState>();

                await authRepo.signOut();
                authState.clearSession();

                if (context.mounted) {
                  Navigator.of(
                    context,
                  ).pushNamedAndRemoveUntil(RouteNames.login, (route) => false);
                }
              },
            ),
          ],
        ),
      ),
    );
  }
}
