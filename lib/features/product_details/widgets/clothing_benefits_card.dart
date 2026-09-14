import 'package:flutter/material.dart';
import '../../../core/constants/delivery_constants.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// The returns/payments/delivery-fee strip on clothing Product Details.
/// The delivery-fee item reads [DeliveryConstants.deliveryFeeLabel] — the
/// same flat fee the cart and checkout actually charge — never a hardcoded
/// "free above Rs X" claim (see that constant's doc comment).
class ClothingBenefitsCard extends StatelessWidget {
  const ClothingBenefitsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildBenefitItem(Icons.history, '7-Day Easy Returns'),
            const _BenefitDivider(),
            _buildBenefitItem(Icons.lock_outline, 'Secure Payments'),
            const _BenefitDivider(),
            _buildBenefitItem(
              Icons.local_shipping_outlined,
              DeliveryConstants.deliveryFeeLabel,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String text) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.left,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BenefitDivider extends StatelessWidget {
  const _BenefitDivider();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 4),
      child: VerticalDivider(
        width: 1,
        thickness: 1,
        color: AppColors.neutralMediumLight,
      ),
    );
  }
}
