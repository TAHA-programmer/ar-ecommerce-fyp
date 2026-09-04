import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/models/product/product_summary_model.dart';
import '../../../../core/widgets/product_image_view.dart';
import 'card_primitives.dart';
import '../../../../app/routes/route_names.dart';

class VerticalProductCard extends StatelessWidget {
  final ProductSummaryModel product;
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;
  final VoidCallback? onAddToCart;
  final double width;
  final double aspectRatio;
  final EdgeInsetsGeometry? margin;

  const VerticalProductCard({
    super.key,
    required this.product,
    required this.isFavorite,
    required this.onFavoriteToggle,
    this.onAddToCart,
    this.width = 140,
    this.aspectRatio = 4 / 5,
    this.margin = const EdgeInsets.only(right: 12),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        Navigator.pushNamed(
          context,
          RouteNames.productDetails,
          arguments: product.id,
        );
      },
      child: Container(
        width: width,
        margin: margin,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withValues(alpha: 0.3),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image Stack
            Padding(
              padding: const EdgeInsets.all(6.0),
              child: AspectRatio(
                aspectRatio: aspectRatio,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(10),
                      child: ProductImageView(
                        imageRef: product.image,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      left: 8,
                      child: ProductBadge(
                        isAr: product.arEnabled,
                        isTryOn: product.tryOnEnabled,
                      ),
                    ),
                    Positioned(
                      top: 8,
                      right: 8,
                      child: FavoriteButton(
                        isFavorite: isFavorite,
                        onTap: onFavoriteToggle,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            // Details
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 4),
                  RatingRow(
                    rating: product.rating,
                    reviewCount: product.reviewCount,
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (product.originalPrice != null)
                              Text(
                                product.originalPrice!,
                                style: const TextStyle(
                                  fontSize: 10,
                                  color: AppColors.textSecondary,
                                  decoration: TextDecoration.lineThrough,
                                ),
                              ),
                            Text(
                              product.currentPrice,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: AppColors.primary,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (onAddToCart != null)
                        AddToCartButton(onTap: onAddToCart!),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
