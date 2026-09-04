import 'package:flutter/material.dart';

import '../../../../core/models/product/product_experience_type.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_sizes.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/product_image_view.dart';

class AdminMediaProductSelector extends StatelessWidget {
  final ProductModel selectedProduct;
  final VoidCallback onTap;

  const AdminMediaProductSelector({
    super.key,
    required this.selectedProduct,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Select Product', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        Material(
          color: AppColors.surface,
          borderRadius: AppRadii.mediumBorder,
          child: InkWell(
            key: const Key('ar_media_product_selector'),
            onTap: onTap,
            borderRadius: AppRadii.mediumBorder,
            child: Container(
              padding: const EdgeInsets.all(AppSpacing.s),
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary),
                borderRadius: AppRadii.mediumBorder,
              ),
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: AppRadii.smallBorder,
                    child: ProductImageView(
                      imageRef: selectedProduct.mainImage,
                      width: AppSizes.minTouchTarget,
                      height: AppSizes.minTouchTarget,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          selectedProduct.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Text(selectedProduct.sku, style: AppTypography.caption),
                        Text(
                          selectedProduct.experienceType.displayName,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.keyboard_arrow_down,
                    color: AppColors.primaryDark,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class AdminMediaProductOption extends StatelessWidget {
  final ProductModel product;
  final bool isSelected;
  final VoidCallback onTap;

  const AdminMediaProductOption({
    super.key,
    required this.product,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      minTileHeight: 72,
      leading: ClipRRect(
        borderRadius: AppRadii.smallBorder,
        child: ProductImageView(
          imageRef: product.mainImage,
          width: AppSizes.minTouchTarget,
          height: AppSizes.minTouchTarget,
        ),
      ),
      title: Text(
        product.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
      ),
      subtitle: Text(
        '${product.sku}\n${product.experienceType.displayName}',
        style: AppTypography.bodySmall,
      ),
      trailing: isSelected
          ? const Icon(Icons.check_circle, color: AppColors.primary)
          : null,
    );
  }
}
