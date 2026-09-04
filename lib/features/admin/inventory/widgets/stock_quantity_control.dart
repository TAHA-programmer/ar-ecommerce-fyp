import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_typography.dart';

/// Compact minus / direct-input / plus stepper for editing a staged stock
/// quantity. The [controller] is owned by the caller so it survives list
/// rebuilds without being recreated on every build.
class StockQuantityControl extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onDecrement;
  final VoidCallback onIncrement;
  final ValueChanged<String> onChanged;
  final bool hasError;

  const StockQuantityControl({
    super.key,
    required this.controller,
    required this.onDecrement,
    required this.onIncrement,
    required this.onChanged,
    this.hasError = false,
  });

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError ? AppColors.error : AppColors.primary;

    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: hasError ? 1.5 : 1),
        borderRadius: AppRadii.mediumBorder,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _StepperButton(icon: Icons.remove, onTap: onDecrement),
          SizedBox(
            width: 44,
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              textAlign: TextAlign.center,
              keyboardType: const TextInputType.numberWithOptions(
                signed: true,
                decimal: true,
              ),
              inputFormatters: [
                // Allow digits, a single leading '-', and a single '.' so
                // negative/decimal entry can still reach the ViewModel and
                // surface its inline "cannot be negative" / "whole numbers
                // only" validation messages, matching the Figma behavior.
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
              ],
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
              decoration: const InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          _StepperButton(icon: Icons.add, onTap: onIncrement),
        ],
      ),
    );
  }
}

class _StepperButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _StepperButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        width: 36,
        height: 40,
        child: Icon(icon, size: 18, color: AppColors.primaryDark),
      ),
    );
  }
}
