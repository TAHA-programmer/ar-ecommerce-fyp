import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/widgets/product_image_view.dart';

class AdminRecentProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback? onTap;

  const AdminRecentProductCard({super.key, required this.product, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy');
    final formattedDate = dateFormat.format(product.addedDate);
    final price = CurrencyFormatter.format(product.priceAmount);

    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.mediumBorder,
      child: Container(
        width: 140, // Fixed width for horizontal scrolling
        padding: const EdgeInsets.all(AppSpacing.s),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.mediumBorder,
          border: Border.all(color: AppColors.primary),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image
            Container(
              height: 100,
              width: double.infinity,
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppRadii.smallBorder,
              ),
              clipBehavior: Clip.antiAlias,
              child: ProductImageView(imageRef: product.mainImage),
            ),
            const SizedBox(height: AppSpacing.s),

            // Name
            Text(
              product.title,
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xxs),

            // Date
            Text(
              formattedDate,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 10,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: AppSpacing.xxs),

            // Price
            Text(
              price,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w600,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
