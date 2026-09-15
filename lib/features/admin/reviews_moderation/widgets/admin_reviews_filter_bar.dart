import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../models/admin_review_filter.dart';

/// The All/Flagged/Published/Hidden/Rejected status filter row on the Admin
/// Reviews screen (Ratings/Reviews v1 Stage 8) - matches this app's
/// established selector-chip vocabulary
/// (`ReviewSortSelector`/`AdminOrderStatusSelector`). [flaggedCount] renders
/// a small badge on the "Flagged" chip so the priority queue is visible at
/// a glance without opening it.
class AdminReviewsFilterBar extends StatelessWidget {
  final AdminReviewFilter selected;
  final int flaggedCount;
  final ValueChanged<AdminReviewFilter> onChanged;

  const AdminReviewsFilterBar({
    super.key,
    required this.selected,
    required this.flaggedCount,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final filter in AdminReviewFilter.values) ...[
            _FilterChip(
              key: Key('admin_reviews_filter_chip_${filter.name}'),
              label: filter.label,
              badgeCount: filter == AdminReviewFilter.flagged
                  ? flaggedCount
                  : null,
              isSelected: filter == selected,
              onTap: () => onChanged(filter),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final int? badgeCount;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterChip({
    super.key,
    required this.label,
    required this.badgeCount,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final showBadge = badgeCount != null && badgeCount! > 0;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: AppRadii.pillBorder,
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.neutralMediumLight,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: AppTypography.bodySmall.copyWith(
                color: isSelected ? AppColors.white : AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (showBadge) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected ? AppColors.white : AppColors.warning,
                  borderRadius: AppRadii.pillBorder,
                ),
                child: Text(
                  '$badgeCount',
                  style: AppTypography.caption.copyWith(
                    color: isSelected ? AppColors.primary : AppColors.white,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
