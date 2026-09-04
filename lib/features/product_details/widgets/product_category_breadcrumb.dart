import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// Displays the product's resolved category name - the caller (see
/// `ProductDetailsViewModel.categoryDisplayName`) is responsible for
/// resolving the real category name via `CategoryRepository`, falling back
/// to the denormalized `categoryKind.label` when unresolvable, per Phase
/// 8.8b's category-name display decision. This widget just renders the
/// already-resolved string - it no longer knows about `ProductCategory` at
/// all.
class ProductCategoryBreadcrumb extends StatelessWidget {
  final String categoryName;
  final String subcategory;

  const ProductCategoryBreadcrumb({
    super.key,
    required this.categoryName,
    required this.subcategory,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: RichText(
        text: TextSpan(
          style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
          children: [
            const TextSpan(text: 'Category: '),
            TextSpan(
              text: categoryName,
              style: const TextStyle(color: AppColors.primary),
            ),
            if (subcategory.isNotEmpty) ...[
              const TextSpan(text: ' > '),
              TextSpan(text: subcategory),
            ],
          ],
        ),
      ),
    );
  }
}
