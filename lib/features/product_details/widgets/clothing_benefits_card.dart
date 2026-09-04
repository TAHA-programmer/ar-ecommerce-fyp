import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class ClothingBenefitsCard extends StatelessWidget {
  const ClothingBenefitsCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _buildBenefitItem(Icons.history, '7-Day Easy Returns'),
          Container(width: 1, height: 24, color: AppColors.neutralMediumLight),
          _buildBenefitItem(Icons.lock_outline, 'Secure Payments'),
          Container(width: 1, height: 24, color: AppColors.neutralMediumLight),
          _buildBenefitItem(
            Icons.shield_outlined,
            'Free Shipping\nabove Rs 999',
          ),
        ],
      ),
    );
  }

  Widget _buildBenefitItem(IconData icon, String text) {
    return Expanded(
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(icon, color: AppColors.primary, size: 16),
          const SizedBox(width: 8),
          Flexible(
            child: Text(
              text,
              textAlign: TextAlign.left,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                fontSize: 10,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
