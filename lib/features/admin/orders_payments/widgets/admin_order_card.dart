import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/order/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/order_id_formatter.dart';

class AdminOrderCard extends StatelessWidget {
  final OrderModel order;
  final VoidCallback onViewDetails;

  const AdminOrderCard({
    super.key,
    required this.order,
    required this.onViewDetails,
  });

  ({IconData icon, Color color}) _orderStatusStyle(OrderStatus status) {
    switch (status) {
      case OrderStatus.pending:
        return (icon: Icons.schedule, color: AppColors.warning);
      case OrderStatus.confirmed:
        return (icon: Icons.inventory_2_outlined, color: AppColors.info);
      case OrderStatus.shipped:
        return (icon: Icons.local_shipping_outlined, color: AppColors.info);
      case OrderStatus.delivered:
        return (icon: Icons.check_circle_outline, color: AppColors.success);
      case OrderStatus.cancelled:
        return (icon: Icons.cancel_outlined, color: AppColors.error);
    }
  }

  Color _paymentStatusColor(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return AppColors.success;
      case PaymentStatus.pending:
        return AppColors.warning;
      case PaymentStatus.failed:
        return AppColors.error;
    }
  }

  @override
  Widget build(BuildContext context) {
    final orderStyle = _orderStatusStyle(order.orderStatus);
    final paymentColor = _paymentStatusColor(order.paymentStatus);
    final formattedDate = DateFormat(
      'MMM dd, yyyy • hh:mm a',
    ).format(order.orderDate);

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.largeBorder,
        border: Border.all(color: AppColors.primary),
      ),
      padding: const EdgeInsets.all(AppSpacing.m),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: orderStyle.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(orderStyle.icon, color: orderStyle.color),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      OrderIdFormatter.short(order.id),
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      order.deliveryAddress.fullName,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Row(
                      children: [
                        const Icon(
                          Icons.calendar_today_outlined,
                          size: 12,
                          color: AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSpacing.xxs),
                        Expanded(
                          child: Text(
                            formattedDate,
                            style: AppTypography.caption,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                CurrencyFormatter.format(order.total),
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xxs,
            children: [
              _Badge(
                label: order.paymentMethod.displayName,
                color: AppColors.primaryDark,
              ),
              _Badge(
                label: order.paymentStatus.displayName,
                color: paymentColor,
              ),
              _Badge(
                label: order.orderStatus.displayName,
                color: orderStyle.color,
                icon: orderStyle.icon,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          const Divider(height: 1, color: AppColors.neutralLight),
          const SizedBox(height: AppSpacing.xs),
          InkWell(
            onTap: onViewDetails,
            child: Row(
              children: [
                Text(
                  'View Details',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.primaryDark,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                const Icon(
                  Icons.chevron_right,
                  size: 16,
                  color: AppColors.primaryDark,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Badge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _Badge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadii.smallBorder,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }
}
