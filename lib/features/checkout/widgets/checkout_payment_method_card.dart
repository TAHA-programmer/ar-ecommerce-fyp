import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class CheckoutPaymentMethodCard extends StatelessWidget {
  const CheckoutPaymentMethodCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.primary,
          width: 2,
        ), // Selected state
      ),
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          const Icon(Icons.credit_card, color: AppColors.primary),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Credit / Debit Card',
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
          ),
          const Icon(Icons.radio_button_checked, color: AppColors.primary),
        ],
      ),
    );
  }
}
