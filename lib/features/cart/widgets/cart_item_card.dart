import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/product_image_view.dart';
import '../models/populated_cart_item.dart';
import 'package:intl/intl.dart';
import 'cart_quantity_control.dart';

class CartItemCard extends StatelessWidget {
  final PopulatedCartItem populatedItem;
  final ValueChanged<int> onQuantityChanged;
  final VoidCallback onRemove;

  /// Phase 8.11a: a short warning ("Out of stock" / "Only N available") shown
  /// inline on this line when its product is out of stock or the aggregated
  /// requested quantity exceeds current stock. `null` = no issue.
  final String? stockWarning;

  const CartItemCard({
    super.key,
    required this.populatedItem,
    required this.onQuantityChanged,
    required this.onRemove,
    this.stockWarning,
  });

  @override
  Widget build(BuildContext context) {
    final item = populatedItem.cartItem;
    final product = populatedItem.product;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neutralLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Image
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: ProductImageView(
              imageRef: product.summary.image,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          // Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        product.summary.title,
                        style: AppTypography.bodyLarge.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: onRemove,
                      behavior: HitTestBehavior.opaque,
                      child: const Icon(
                        Icons.close,
                        size: 20,
                        color: AppColors.textSecondary,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 4),
                // Variants
                if (item.selectedSize != null || item.selectedColor != null)
                  Text(
                    [
                      if (item.selectedSize != null)
                        'Size: ${item.selectedSize!.name}',
                      if (item.selectedColor != null)
                        'Color: ${item.selectedColor!.name}',
                    ].join('  |  '),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                if (stockWarning != null) ...[
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 14,
                        color: AppColors.error,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          stockWarning!,
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      product.summary.currentPrice,
                      style: AppTypography.bodyLarge.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primaryDark,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        CartQuantityControl(
                          quantity: item.quantity,
                          onQuantityChanged: onQuantityChanged,
                        ),
                        if (item.quantity > 1) ...[
                          const SizedBox(height: 4),
                          Builder(
                            builder: (context) {
                              final priceStr = product.summary.currentPrice
                                  .replaceAll(RegExp(r'[^0-9.]'), '');
                              final unitPrice =
                                  double.tryParse(priceStr) ?? 0.0;
                              final totalItemPrice = unitPrice * item.quantity;
                              final format = NumberFormat.decimalPattern(
                                'en_IN',
                              );
                              final totalStr =
                                  'Rs ${format.format(totalItemPrice)}/-';
                              return Text(
                                totalStr,
                                style: AppTypography.bodyMedium.copyWith(
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.primaryDark,
                                ),
                              );
                            },
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
