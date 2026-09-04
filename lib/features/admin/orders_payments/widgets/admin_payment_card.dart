import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/order/order_model.dart';
import '../../../../core/models/order/payment_record.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/order_id_formatter.dart';

class AdminPaymentCard extends StatelessWidget {
  final PaymentRecord payment;
  final OrderModel? linkedOrder;

  const AdminPaymentCard({
    super.key,
    required this.payment,
    required this.linkedOrder,
  });

  ({IconData icon, Color color}) _statusStyle(PaymentStatus status) {
    switch (status) {
      case PaymentStatus.paid:
        return (icon: Icons.check_circle_outline, color: AppColors.success);
      case PaymentStatus.pending:
        return (icon: Icons.schedule, color: AppColors.warning);
      case PaymentStatus.failed:
        return (icon: Icons.cancel_outlined, color: AppColors.error);
    }
  }

  @override
  Widget build(BuildContext context) {
    final style = _statusStyle(payment.status);
    final formattedDate = DateFormat(
      'MMM dd, yyyy • hh:mm a',
    ).format(payment.createdAt);
    // Phase 8.9: payment.orderId is always present now (no longer
    // nullable), but it can still point at an order that doesn't resolve
    // (e.g. a data inconsistency) - the safe "—" fallback is keyed off
    // whether the order actually RESOLVED (linkedOrder), not off orderId's
    // own presence, mirroring customerLabel's existing convention below.
    final orderLabel = linkedOrder != null
        ? OrderIdFormatter.short(payment.orderId)
        : '—';
    final customerLabel = linkedOrder?.deliveryAddress.fullName ?? '—';

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
                  color: style.color.withValues(alpha: 0.1),
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, color: style.color),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      OrderIdFormatter.short(payment.paymentId),
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Order: $orderLabel',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      'Customer: $customerLabel',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                CurrencyFormatter.format(payment.amount),
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
                label: payment.status.displayName,
                color: style.color,
                icon: style.icon,
              ),
              _Badge(
                label: payment.method.displayName,
                color: AppColors.primaryDark,
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          const Divider(height: 1, color: AppColors.neutralLight),
          const SizedBox(height: AppSpacing.xs),
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
