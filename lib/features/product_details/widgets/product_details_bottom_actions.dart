import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/models/product/product_experience_type.dart';

class ProductDetailsBottomActions extends StatelessWidget {
  final ProductExperienceType experienceType;
  final String price;
  final VoidCallback onAddToCart;
  final VoidCallback onViewInRoom;
  final VoidCallback onTryItOn;

  /// Phase 8.11a: when `true`, every "Add to Cart" affordance is disabled and
  /// relabelled "Out of Stock". The AR/VTO preview buttons stay enabled - a
  /// customer can still view an out-of-stock item in their room / try it on.
  final bool isOutOfStock;

  const ProductDetailsBottomActions({
    super.key,
    required this.experienceType,
    required this.price,
    required this.onAddToCart,
    required this.onViewInRoom,
    required this.onTryItOn,
    this.isOutOfStock = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 24,
        right: 24,
        top: 16,
        bottom: 16 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: const Border(
          top: BorderSide(color: AppColors.neutralMediumLight),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            offset: const Offset(0, -4),
            blurRadius: 8,
          ),
        ],
      ),
      child: Row(
        children: [
          if (experienceType == ProductExperienceType.virtualTryOn) ...[
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: onTryItOn,
                  icon: const Icon(
                    Icons.document_scanner_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    'Try It On',
                    style: AppTypography.label.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: isOutOfStock ? null : onAddToCart,
                  icon: const Icon(
                    Icons.shopping_cart_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  label: Text(
                    isOutOfStock ? 'Out of Stock' : 'Add to Cart',
                    style: AppTypography.label.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ] else if (experienceType == ProductExperienceType.roomAr) ...[
            Expanded(
              child: SizedBox(
                height: 48,
                child: OutlinedButton.icon(
                  onPressed: onViewInRoom,
                  icon: const Icon(
                    Icons.view_in_ar_outlined,
                    color: AppColors.primary,
                    size: 20,
                  ),
                  label: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      'View in Your Room',
                      style: AppTypography.label.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isOutOfStock ? null : onAddToCart,
                  icon: const Icon(
                    Icons.shopping_cart_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    isOutOfStock ? 'Out of Stock' : 'Add to Cart',
                    style: AppTypography.label.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ] else ...[
            // Fallback if no AR/TryOn
            Expanded(
              child: SizedBox(
                height: 48,
                child: ElevatedButton.icon(
                  onPressed: isOutOfStock ? null : onAddToCart,
                  icon: const Icon(
                    Icons.shopping_cart_outlined,
                    color: Colors.white,
                    size: 20,
                  ),
                  label: Text(
                    isOutOfStock ? 'Out of Stock' : 'Add to Cart',
                    style: AppTypography.label.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
