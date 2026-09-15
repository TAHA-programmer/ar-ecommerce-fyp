import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../models/review_sort_option.dart';

extension on ReviewSortOption {
  String get label {
    switch (this) {
      case ReviewSortOption.newest:
        return 'Newest';
      case ReviewSortOption.highestRating:
        return 'Highest Rated';
      case ReviewSortOption.lowestRating:
        return 'Lowest Rated';
    }
  }
}

/// The Newest/Highest Rated/Lowest Rated sort control (Ratings/Reviews v1
/// §0 decision 9 - default newest-first) - a row of selectable pill chips,
/// matching this screen's established selector vocabulary
/// (`ProductColorSelector`/`ProductSizeSelector`).
class ReviewSortSelector extends StatelessWidget {
  final ReviewSortOption selected;
  final ValueChanged<ReviewSortOption> onChanged;

  const ReviewSortSelector({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final option in ReviewSortOption.values) ...[
            _SortChip(
              label: option.label,
              isSelected: option == selected,
              onTap: () => onChanged(option),
            ),
            const SizedBox(width: 8),
          ],
        ],
      ),
    );
  }
}

class _SortChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _SortChip({
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.neutralMediumLight,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: isSelected ? AppColors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
