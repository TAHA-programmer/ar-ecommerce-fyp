import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class CartQuantityControl extends StatelessWidget {
  final int quantity;
  final ValueChanged<int> onQuantityChanged;

  /// When `false`, the "+" control is greyed to signal the available-stock
  /// limit has been reached — mirrors `ProductQuantitySelector.canIncrement`.
  /// The tap still fires `onQuantityChanged(quantity + 1)` so the caller can
  /// surface a clean "Only N available." message instead of silently doing
  /// nothing.
  final bool canIncrement;

  const CartQuantityControl({
    super.key,
    required this.quantity,
    required this.onQuantityChanged,
    this.canIncrement = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.neutralLight.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildButton(
            icon: Icons.remove,
            onTap: () {
              if (quantity > 1) {
                onQuantityChanged(quantity - 1);
              }
            },
            enabled: quantity > 1,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Text(
              '$quantity',
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          _buildButton(
            icon: Icons.add,
            onTap: () => onQuantityChanged(quantity + 1),
            enabled: canIncrement,
            // The tap must still reach the caller at the stock cap so it can
            // surface "Only N available." — only the icon greys out.
            blockTapWhenDisabled: false,
          ),
        ],
      ),
    );
  }

  Widget _buildButton({
    required IconData icon,
    required VoidCallback onTap,
    required bool enabled,
    bool blockTapWhenDisabled = true,
  }) {
    return GestureDetector(
      onTap: (enabled || !blockTapWhenDisabled) ? onTap : null,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(4),
        margin: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: AppColors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: AppColors.black.withValues(alpha: 0.05),
              offset: const Offset(0, 1),
              blurRadius: 2,
            ),
          ],
        ),
        child: Icon(
          icon,
          size: 16,
          color: enabled ? AppColors.textPrimary : AppColors.neutralMediumLight,
        ),
      ),
    );
  }
}
