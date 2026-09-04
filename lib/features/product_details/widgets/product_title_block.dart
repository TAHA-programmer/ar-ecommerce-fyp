import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/models/product/product_category.dart';
import '../models/product_detail_model.dart';

class ProductTitleBlock extends StatelessWidget {
  final ProductDetailModel product;

  const ProductTitleBlock({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final isClothing = product.categoryKind == ProductCategory.clothing;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  product.summary.title,
                  style: AppTypography.headingMedium.copyWith(height: 1.2),
                ),
              ),
              if (isClothing)
                Padding(
                  padding: const EdgeInsets.only(top: 4.0),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${product.summary.rating}',
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(
                        Icons.star_rounded,
                        color: Colors.black87,
                        size: 16,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        '(${product.summary.reviewCount})',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: Wrap(
                  crossAxisAlignment: WrapCrossAlignment.center,
                  spacing: 8.0,
                  runSpacing: 4.0,
                  children: [
                    Text(
                      product.summary.currentPrice,
                      style: AppTypography.title.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (product.summary.originalPrice != null)
                      Text(
                        product.summary.originalPrice!,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                          decoration: TextDecoration.lineThrough,
                        ),
                      ),
                    if (product.summary.discountPercentage != null)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          product.summary.discountPercentage!,
                          style: AppTypography.label.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              _StockIndicator(
                stockQuantity: product.stockQuantity,
                isClothing: isClothing,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// The stock-information line in the title block. Shows the exact current
/// stock ("6 available") when in stock, or "Out of Stock" when `0` - wired
/// straight to the real [ProductDetailModel.stockQuantity], never hardcoded.
/// Keeps the pre-existing visual language: an optional leading icon for the
/// furniture layout, plain coloured text for the clothing layout.
class _StockIndicator extends StatelessWidget {
  final int stockQuantity;
  final bool isClothing;

  const _StockIndicator({
    required this.stockQuantity,
    required this.isClothing,
  });

  @override
  Widget build(BuildContext context) {
    final bool outOfStock = stockQuantity <= 0;
    final Color color = outOfStock
        ? AppColors.error
        : (isClothing ? Colors.green[700]! : AppColors.primary);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!isClothing) ...[
          Icon(
            outOfStock ? Icons.cancel : Icons.check_circle,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 4),
        ],
        Text(
          outOfStock ? 'Out of Stock' : '$stockQuantity available',
          style: AppTypography.bodySmall.copyWith(
            color: color,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
