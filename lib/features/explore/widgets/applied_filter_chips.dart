import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/explore_filter_state.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';

class AppliedFilterChips extends StatelessWidget {
  final ExploreFilterState filterState;
  final VoidCallback onClearAll;
  final ValueChanged<ExploreFilterState> onFilterRemoved;

  const AppliedFilterChips({
    super.key,
    required this.filterState,
    required this.onClearAll,
    required this.onFilterRemoved,
  });

  @override
  Widget build(BuildContext context) {
    if (!filterState.hasActiveFilters) {
      return const SizedBox.shrink();
    }

    final List<Widget> chips = [];

    // Add In Stock chip
    if (filterState.inStockOnly) {
      chips.add(
        _buildChip('In Stock', () {
          onFilterRemoved(filterState.copyWith(inStockOnly: false));
        }),
      );
    }

    // Add AR chip
    if (filterState.arAvailable) {
      chips.add(
        _buildChip('AR Available', () {
          onFilterRemoved(filterState.copyWith(arAvailable: false));
        }),
      );
    }

    // Add Try-On chip
    if (filterState.tryOnAvailable) {
      chips.add(
        _buildChip('Try-On Available', () {
          onFilterRemoved(filterState.copyWith(tryOnAvailable: false));
        }),
      );
    }

    // Add Colors
    for (final color in filterState.selectedColors) {
      final colorName = color.name[0].toUpperCase() + color.name.substring(1);
      chips.add(
        _buildChip(colorName, () {
          final newColors = Set<ProductColorOption>.from(
            filterState.selectedColors,
          )..remove(color);
          onFilterRemoved(filterState.copyWith(selectedColors: newColors));
        }),
      );
    }

    // Add Sizes
    for (final size in filterState.selectedSizes) {
      chips.add(
        _buildChip('Size ${size.label}', () {
          final newSizes = Set<ProductSize>.from(filterState.selectedSizes)
            ..remove(size);
          onFilterRemoved(filterState.copyWith(selectedSizes: newSizes));
        }),
      );
    }

    // Add Price Range if modified from default
    if (filterState.minimumPrice > 0 || filterState.maximumPrice < 50000) {
      chips.add(
        _buildChip(
          'Rs ${filterState.minimumPrice.toInt()} - Rs ${filterState.maximumPrice.toInt()}',
          () {
            onFilterRemoved(
              filterState.copyWith(minimumPrice: 0, maximumPrice: 50000),
            );
          },
        ),
      );
    }

    if (chips.isEmpty) {
      return const SizedBox.shrink();
    }

    return Padding(
      padding: const EdgeInsets.only(left: 16, right: 16, top: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onClearAll,
            child: const Padding(
              padding: EdgeInsets.symmetric(vertical: 6), // Align with chips
              child: Text(
                'Clear All',
                style: TextStyle(
                  fontFamily: 'Inter',
                  color: AppColors.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, VoidCallback onRemove) {
    return Container(
      padding: const EdgeInsets.only(left: 10, right: 4, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.15), // Pale lime
        borderRadius: BorderRadius.circular(6), // modest radius
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontFamily: 'Inter',
              color: AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(width: 4),
          GestureDetector(
            onTap: onRemove,
            behavior: HitTestBehavior.opaque,
            child: const Padding(
              padding: EdgeInsets.all(4.0),
              child: Icon(Icons.close, size: 14, color: AppColors.textPrimary),
            ),
          ),
        ],
      ),
    );
  }
}
