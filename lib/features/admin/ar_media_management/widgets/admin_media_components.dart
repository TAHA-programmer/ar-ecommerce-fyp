import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_shadows.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Shared chrome for the Admin AR & Media cards. Only the two pieces both the
/// Room-AR ([AdminRoomArModelCard]) and Virtual Try-On ([AdminVtoGarmentCard])
/// cards still use live here — the pre-9.3 mock helpers (upload tile, status
/// pill, configuration status, action row) were removed with the mock VTO card.

class AdminMediaCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const AdminMediaCard({
    super.key,
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.largeBorder,
        border: Border.all(color: AppColors.primary),
        boxShadow: AppShadows.subtle,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: AppSizes.minTouchTarget,
                height: AppSizes.minTouchTarget,
                decoration: BoxDecoration(
                  color: AppColors.primaryLight.withValues(alpha: 0.18),
                  borderRadius: AppRadii.mediumBorder,
                ),
                child: Icon(icon, color: AppColors.primaryDark),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Text(
                  title,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.m),
          child,
        ],
      ),
    );
  }
}

class AdminMediaPreview extends StatelessWidget {
  final Widget child;
  final String label;

  const AdminMediaPreview({
    super.key,
    required this.child,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.neutralLight,
        borderRadius: AppRadii.largeBorder,
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            left: AppSpacing.xs,
            bottom: AppSpacing.xs,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.xs,
                vertical: AppSpacing.xxs,
              ),
              decoration: BoxDecoration(
                color: AppColors.white.withValues(alpha: 0.9),
                borderRadius: AppRadii.smallBorder,
              ),
              child: Text(label, style: AppTypography.caption),
            ),
          ),
        ],
      ),
    );
  }
}
