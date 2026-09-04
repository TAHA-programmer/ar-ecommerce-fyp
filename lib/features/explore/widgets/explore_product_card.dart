import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/product_image_view.dart';
import '../models/catalog_product_model.dart';
import '../../home/widgets/cards/card_primitives.dart';

class ExploreProductCard extends StatelessWidget {
  final CatalogProductModel product;
  final bool isFavorite;
  final VoidCallback onFavoriteTap;
  final VoidCallback onAddToCartTap;
  final VoidCallback onTap;

  const ExploreProductCard({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onFavoriteTap,
    required this.onAddToCartTap,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.15),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8.0), // Inner inset padding
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Image with Badges
              Expanded(
                child: Stack(
                  children: [
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(12),
                        color: AppColors.surface, // Background for image area
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: ProductImageView(
                          imageRef: product.summary.image,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: ProductBadge(
                        isAr: product.summary.arEnabled,
                        isTryOn: product.summary.tryOnEnabled,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: FavoriteButton(
                        isFavorite: isFavorite,
                        onTap: onFavoriteTap,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              // Info Area
              Text(
                product.summary.title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textPrimary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 4),
              Text(
                product.summary.currentPrice,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
              const SizedBox(height: 4),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    product.summary.inStock ? 'In Stock' : 'Out of Stock',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                      color: product.summary.inStock
                          ? AppColors.primary
                          : AppColors.error,
                    ),
                  ),
                  AddToCartButton(onTap: onAddToCartTap),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
