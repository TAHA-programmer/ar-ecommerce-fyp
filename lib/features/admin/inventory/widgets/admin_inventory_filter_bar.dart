import 'package:flutter/material.dart';

import '../../../../core/models/product/product_category.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class AdminInventoryFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final ProductCategory selectedCategory;
  final ValueChanged<ProductCategory> onCategoryChanged;
  final bool lowStockOnly;
  final ValueChanged<bool> onLowStockOnlyChanged;

  const AdminInventoryFilterBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.selectedCategory,
    required this.onCategoryChanged,
    required this.lowStockOnly,
    required this.onLowStockOnlyChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: searchController,
          onChanged: onSearchChanged,
          style: AppTypography.bodySmall,
          decoration: InputDecoration(
            hintText: 'Search products by name, category, or SKU...',
            hintMaxLines: 1,
            hintStyle: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              overflow: TextOverflow.ellipsis,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: AppColors.textSecondary,
            ),
            filled: true,
            fillColor: AppColors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: AppSpacing.m,
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadii.mediumBorder,
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.mediumBorder,
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.mediumBorder,
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Row(
          children: [
            Expanded(child: _buildCategoryDropdown()),
            const SizedBox(width: AppSpacing.s),
            Expanded(child: _buildLowStockToggle()),
          ],
        ),
      ],
    );
  }

  Widget _buildCategoryDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.primary),
        borderRadius: AppRadii.mediumBorder,
        color: AppColors.white,
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<ProductCategory>(
          value: selectedCategory,
          isExpanded: true,
          icon: const Icon(
            Icons.keyboard_arrow_down,
            color: AppColors.primaryDark,
          ),
          style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
          items: ProductCategory.values.map((category) {
            return DropdownMenuItem(
              value: category,
              child: Text(
                category == ProductCategory.all
                    ? 'All Categories'
                    : category.label,
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (value) {
            if (value != null) onCategoryChanged(value);
          },
        ),
      ),
    );
  }

  Widget _buildLowStockToggle() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s),
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.primary),
        borderRadius: AppRadii.mediumBorder,
        color: AppColors.white,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(
            child: Text(
              'Low Stock Only',
              style: AppTypography.bodySmall,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Transform.scale(
            scale: 0.8,
            child: Switch(
              value: lowStockOnly,
              onChanged: onLowStockOnlyChanged,
              activeThumbColor: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}
