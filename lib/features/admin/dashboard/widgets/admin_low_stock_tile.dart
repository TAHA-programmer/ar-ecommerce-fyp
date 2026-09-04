import 'package:flutter/material.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/widgets/product_image_view.dart';

class AdminLowStockTile extends StatelessWidget {
  final ProductModel product;
  final VoidCallback? onTap;

  const AdminLowStockTile({super.key, required this.product, this.onTap});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.largeBorder,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.largeBorder,
            border: Border.all(color: AppColors.primary),
          ),
          child: Row(
            children: [
              // Image
              Container(
                width: 48.0,
                height: 48.0,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: AppRadii.smallBorder,
                ),
                clipBehavior: Clip.antiAlias,
                child: ProductImageView(imageRef: product.mainImage),
              ),
              const SizedBox(width: AppSpacing.m),

              // Middle section (Name + SKU)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'SKU: ${product.sku}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.s),

              // Stock Info
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    'Stock: ${product.stockQuantity}',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.error, // Red text for stock
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Reorder soon',
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),

              const SizedBox(width: AppSpacing.s),

              // Chevron
              const Icon(
                Icons.chevron_right,
                size: 16,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
