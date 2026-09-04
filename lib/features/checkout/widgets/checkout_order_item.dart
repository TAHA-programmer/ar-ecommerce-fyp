import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/product_image_view.dart';
import '../../cart/models/populated_cart_item.dart';
import 'package:intl/intl.dart' as intl;

class CheckoutOrderItem extends StatelessWidget {
  final PopulatedCartItem item;

  const CheckoutOrderItem({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutralMediumLight),
      ),
      padding: const EdgeInsets.all(12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: ProductImageView(
              imageRef: item.product.summary.image,
              width: 80,
              height: 80,
              fit: BoxFit.cover,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.product.summary.title,
                  style: AppTypography.bodyLarge.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                if (item.cartItem.selectedColor != null ||
                    item.cartItem.selectedSize != null)
                  Text(
                    [
                      if (item.cartItem.selectedColor != null)
                        'Color: ${item.cartItem.selectedColor!.name}',
                      if (item.cartItem.selectedSize != null)
                        'Size: ${item.cartItem.selectedSize!.name}',
                    ].join(' | '),
                    style: AppTypography.bodySmall.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Qty: ${item.cartItem.quantity}',
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (item.cartItem.quantity > 1)
                          Text(
                            '${item.product.summary.currentPrice} each',
                            style: AppTypography.caption.copyWith(
                              color: AppColors.textSecondary,
                            ),
                          ),
                        Builder(
                          builder: (context) {
                            if (item.cartItem.quantity > 1) {
                              final priceStr = item.product.summary.currentPrice
                                  .replaceAll(RegExp(r'[^0-9.]'), '');
                              final unitPrice =
                                  double.tryParse(priceStr) ?? 0.0;
                              final totalItemPrice =
                                  unitPrice * item.cartItem.quantity;
                              final format = intl.NumberFormat.decimalPattern(
                                'en_IN',
                              );
                              final totalStr =
                                  'Rs ${format.format(totalItemPrice)}/-';
                              return Text(
                                totalStr,
                                style: AppTypography.bodyLarge.copyWith(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            } else {
                              return Text(
                                item.product.summary.currentPrice,
                                style: AppTypography.bodyLarge.copyWith(
                                  color: AppColors.primaryDark,
                                  fontWeight: FontWeight.w700,
                                ),
                              );
                            }
                          },
                        ),
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
