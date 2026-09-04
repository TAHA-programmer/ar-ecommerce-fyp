import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class ProductQuantitySelector extends StatelessWidget {
  final int quantity;
  final VoidCallback onIncrement;
  final VoidCallback onDecrement;

  /// When `false`, the "+" control is greyed to signal the available-stock
  /// limit has been reached. The tap still fires so the ViewModel can
  /// surface a clean "Only N available." message (Phase 8.11a).
  final bool canIncrement;

  const ProductQuantitySelector({
    super.key,
    required this.quantity,
    required this.onIncrement,
    required this.onDecrement,
    this.canIncrement = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          'Quantity',
          style: AppTypography.bodySmall.copyWith(color: AppColors.textPrimary),
        ),
        Container(
          height: 40,
          width: 120,
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.neutralMediumLight),
            borderRadius: BorderRadius.circular(8),
            color: Colors.white,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              InkWell(
                onTap: onDecrement,
                borderRadius: const BorderRadius.only(
                  topLeft: Radius.circular(8),
                  bottomLeft: Radius.circular(8),
                ),
                child: Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.remove,
                    size: 20,
                    color: quantity > 1
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
              Text(
                '$quantity',
                style: AppTypography.bodySmall.copyWith(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
              InkWell(
                onTap: onIncrement,
                borderRadius: const BorderRadius.only(
                  topRight: Radius.circular(8),
                  bottomRight: Radius.circular(8),
                ),
                child: Container(
                  width: 40,
                  alignment: Alignment.center,
                  child: Icon(
                    Icons.add,
                    size: 20,
                    color: canIncrement
                        ? AppColors.textPrimary
                        : AppColors.textSecondary,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
