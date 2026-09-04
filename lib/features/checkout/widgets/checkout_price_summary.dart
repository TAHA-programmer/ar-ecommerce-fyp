import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import 'package:intl/intl.dart';

class CheckoutPriceSummary extends StatelessWidget {
  final double subtotal;
  final double deliveryFee;
  final double discount;
  final double total;

  const CheckoutPriceSummary({
    super.key,
    required this.subtotal,
    required this.deliveryFee,
    required this.discount,
    required this.total,
  });

  String _formatPrice(double price) {
    final format = NumberFormat.decimalPattern('en_IN');
    return 'Rs ${format.format(price)}/-';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutralMediumLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildRow('Subtotal', _formatPrice(subtotal)),
          const SizedBox(height: 12),
          _buildRow('Delivery Fee', _formatPrice(deliveryFee)),
          const SizedBox(height: 12),
          _buildRow('Discount', '-${_formatPrice(discount)}', isDiscount: true),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Divider(color: AppColors.neutralMediumLight, height: 1),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Total',
                style: AppTypography.title.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
              Text(
                _formatPrice(total),
                style: AppTypography.title.copyWith(
                  fontWeight: FontWeight.bold,
                  color: AppColors.primaryDark,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildRow(String label, String value, {bool isDiscount = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        Text(
          value,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            color: isDiscount ? AppColors.primary : AppColors.textPrimary,
          ),
        ),
      ],
    );
  }
}
