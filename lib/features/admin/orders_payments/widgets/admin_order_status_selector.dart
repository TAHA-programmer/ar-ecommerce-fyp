import 'package:flutter/material.dart';

import '../../../../core/models/order/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class AdminOrderStatusSelector extends StatelessWidget {
  final OrderStatus stagedStatus;
  final bool Function(OrderStatus status) isSelectable;
  final ValueChanged<OrderStatus> onSelect;
  final bool hasPendingChange;
  final VoidCallback onUpdate;
  final VoidCallback onClose;

  const AdminOrderStatusSelector({
    super.key,
    required this.stagedStatus,
    required this.isSelectable,
    required this.onSelect,
    required this.hasPendingChange,
    required this.onUpdate,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Update Order Status',
          style: AppTypography.title.copyWith(fontSize: 14),
        ),
        const SizedBox(height: AppSpacing.m),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: OrderStatus.values.map((status) {
            final isStaged = status == stagedStatus;
            final isEnabled = isSelectable(status);
            return _StatusChip(
              key: Key('admin_order_status_chip_${status.name}'),
              label: status.displayName,
              isSelected: isStaged,
              isEnabled: isEnabled,
              isDestructive: status == OrderStatus.cancelled,
              onTap: isEnabled ? () => onSelect(status) : null,
            );
          }).toList(),
        ),
        const SizedBox(height: AppSpacing.m),
        LayoutBuilder(
          builder: (context, constraints) {
            final updateButton = ElevatedButton(
              key: const Key('admin_order_update_status_button'),
              onPressed: hasPendingChange ? onUpdate : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: AppColors.white,
                disabledBackgroundColor: AppColors.neutralLight,
                disabledForegroundColor: AppColors.textSecondary,
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.mediumBorder,
                ),
                elevation: 0,
              ),
              child: const Text(
                'Update Status',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            );
            final closeButton = OutlinedButton(
              key: const Key('admin_order_close_button'),
              onPressed: onClose,
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadii.mediumBorder,
                ),
              ),
              child: const Text(
                'Close',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            );

            if (constraints.maxWidth > 360) {
              return Row(
                children: [
                  Expanded(child: updateButton),
                  const SizedBox(width: AppSpacing.s),
                  Expanded(child: closeButton),
                ],
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                updateButton,
                const SizedBox(height: AppSpacing.s),
                closeButton,
              ],
            );
          },
        ),
        const SizedBox(height: AppSpacing.s),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.info_outline,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSpacing.xxs),
            Expanded(
              child: Text(
                'Changing an order to Delivered or Cancelled requires confirmation.',
                style: AppTypography.caption,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isEnabled;
  final bool isDestructive;
  final VoidCallback? onTap;

  const _StatusChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.isEnabled,
    required this.isDestructive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final Color activeColor = isDestructive
        ? AppColors.error
        : AppColors.primary;

    Color borderColor;
    Color backgroundColor;
    Color textColor;

    if (!isEnabled) {
      borderColor = AppColors.neutralLight;
      backgroundColor = AppColors.background;
      textColor = AppColors.neutralMedium;
    } else if (isSelected) {
      borderColor = activeColor;
      backgroundColor = activeColor;
      textColor = AppColors.white;
    } else {
      borderColor = activeColor.withValues(alpha: 0.5);
      backgroundColor = AppColors.white;
      textColor = AppColors.textPrimary;
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: AppRadii.pillBorder,
          border: Border.all(color: borderColor),
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: textColor,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
