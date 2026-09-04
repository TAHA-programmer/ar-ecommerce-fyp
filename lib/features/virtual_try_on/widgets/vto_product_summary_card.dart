import 'package:flutter/material.dart';
import '../../product_details/models/product_detail_model.dart';
import '../../../core/models/product/product_vto_model_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/product_image_view.dart';

class VtoProductSummaryCard extends StatelessWidget {
  final ProductDetailModel product;

  const VtoProductSummaryCard({super.key, required this.product});

  @override
  Widget build(BuildContext context) {
    final isFemale = product.vtoModelType == ProductVtoModelType.female;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neutralLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.neutralLight),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: ProductImageView(
                    imageRef: product.summary.image,
                    width: 80,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.summary.title,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        Text(
                          product.summary.currentPrice,
                          style: AppTypography.bodyMedium.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        if (!isFemale && product.summary.originalPrice != null)
                          Text(
                            product.summary.originalPrice!,
                            style: AppTypography.bodySmall.copyWith(
                              decoration: TextDecoration.lineThrough,
                              color: AppColors.textSecondary,
                            ),
                          ),
                        if (!isFemale &&
                            product.summary.discountPercentage != null)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.primary.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              product.summary.discountPercentage!,
                              style: AppTypography.caption.copyWith(
                                color: AppColors.primaryDark,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (isFemale) ...[
                          Text(
                            '|',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.neutralMedium,
                            ),
                          ),
                          Text(
                            'In Stock',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                            size: 14,
                          ),
                        ],
                      ],
                    ),
                    if (!isFemale) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 4,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          const Icon(
                            Icons.check_circle,
                            color: AppColors.primary,
                            size: 14,
                          ),
                          Text(
                            'In Stock',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.primaryDark,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const Text(
                            '•',
                            style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 12,
                            ),
                          ),
                          Text(
                            'Ready to try',
                            style: AppTypography.bodySmall.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.neutralLight),
          const SizedBox(height: 16),
          if (isFemale) _buildFemaleAttributes() else _buildMaleAttributes(),
        ],
      ),
    );
  }

  Widget _buildMaleAttributes() {
    return Column(
      children: [
        Row(
          children: [
            Expanded(
              child: _buildAttributeItem(
                icon: Icons.straighten,
                label: 'Size',
                value: product.defaultSize?.name.toUpperCase() ?? 'M',
              ),
            ),
            Container(width: 1, height: 40, color: AppColors.neutralLight),
            Expanded(
              child: _buildAttributeItem(
                icon: Icons.palette,
                label: 'Color',
                value:
                    product.defaultColor?.name ??
                    'Standard', // Basic string mapping
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildAttributeItem(
                icon: Icons.checkroom,
                label: 'Type',
                value: product.subcategory.isNotEmpty
                    ? product.subcategory
                    : 'Clothing',
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildFemaleAttributes() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        _buildAttributeItem(
          icon: Icons.straighten,
          label: 'Size',
          value: product.defaultSize?.name.toUpperCase() ?? 'M',
        ),
        _buildAttributeItem(
          icon: Icons.lens, // Color dot
          label: 'Color',
          value: product.defaultColor?.name ?? 'Standard',
          iconColor: AppColors.primaryDark,
        ),
        _buildAttributeItem(
          icon: Icons.checkroom,
          label: 'Type',
          value: product.subcategory.isNotEmpty
              ? product.subcategory
              : 'Clothing',
        ),
      ],
    );
  }

  Widget _buildAttributeItem({
    required IconData icon,
    required String label,
    required String value,
    Color? iconColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, size: 16, color: iconColor ?? AppColors.textSecondary),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTypography.caption),
            Text(
              value,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
