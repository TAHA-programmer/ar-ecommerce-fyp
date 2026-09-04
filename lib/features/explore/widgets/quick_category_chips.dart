import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../core/models/product/product_category.dart';

class QuickCategoryChips extends StatelessWidget {
  final ProductCategory activeCategory;
  final ValueChanged<ProductCategory> onCategorySelected;

  const QuickCategoryChips({
    super.key,
    required this.activeCategory,
    required this.onCategorySelected,
  });

  // The categories to display in the quick row
  static const List<ProductCategory> _visibleCategories = [
    ProductCategory.all,
    ProductCategory.furniture,
    ProductCategory.clothing,
    ProductCategory.rugs,
    ProductCategory.decor,
  ];

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        scrollDirection: Axis.horizontal,
        itemCount: _visibleCategories.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final category = _visibleCategories[index];
          final isSelected = activeCategory == category;

          return GestureDetector(
            onTap: () => onCategorySelected(category),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(6), // Rectangular, not pill
                border: Border.all(
                  color: isSelected
                      ? AppColors.primary
                      : AppColors.neutralLight,
                  width: 1,
                ),
              ),
              child: Center(
                child: Text(
                  category.label,
                  style: TextStyle(
                    fontFamily: 'Inter',
                    color: AppColors.textPrimary, // Always dark text
                    fontSize: 13,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
