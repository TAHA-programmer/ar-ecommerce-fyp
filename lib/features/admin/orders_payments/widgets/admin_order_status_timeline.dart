import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/order/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Admin-owned vertical status timeline. Deliberately separate from the
/// Customer-facing horizontal `OrderStatusTimeline` (approved, unmodified) -
/// this widget renders the same lifecycle data in the vertical layout the
/// Admin Order Detail Figma calls for.
class AdminOrderStatusTimeline extends StatelessWidget {
  final OrderStatus currentStatus;
  final DateTime orderDate;

  const AdminOrderStatusTimeline({
    super.key,
    required this.currentStatus,
    required this.orderDate,
  });

  static const List<OrderStatus> _progressSteps = [
    OrderStatus.pending,
    OrderStatus.confirmed,
    OrderStatus.shipped,
    OrderStatus.delivered,
  ];

  @override
  Widget build(BuildContext context) {
    if (currentStatus == OrderStatus.cancelled) {
      // A cancelled order never pretends to have progressed through later
      // delivery stages - only "Order placed" then "Cancelled" are shown.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildStep(
            title: 'Order placed',
            date: orderDate,
            isCompleted: true,
            isCurrent: false,
            isLast: false,
          ),
          _buildStep(
            title: 'Cancelled',
            date: null,
            isCompleted: true,
            isCurrent: true,
            isLast: true,
            isError: true,
          ),
        ],
      );
    }

    final currentIndex = _progressSteps.indexOf(currentStatus);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (int i = 0; i < _progressSteps.length; i++)
          _buildStep(
            title: i == 0 ? 'Order placed' : _progressSteps[i].displayName,
            date: i == 0 ? orderDate : null,
            isCompleted: i < currentIndex,
            isCurrent: i == currentIndex,
            isLast: i == _progressSteps.length - 1,
          ),
      ],
    );
  }

  Widget _buildStep({
    required String title,
    required DateTime? date,
    required bool isCompleted,
    required bool isCurrent,
    required bool isLast,
    bool isError = false,
  }) {
    final Color color = isError
        ? AppColors.error
        : (isCompleted || isCurrent
              ? AppColors.primary
              : AppColors.neutralMedium);

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Column(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isCompleted || isCurrent
                      ? color
                      : AppColors.background,
                  border: Border.all(color: color, width: 2),
                ),
              ),
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 2,
                    color: isCompleted
                        ? AppColors.primary
                        : AppColors.neutralLight,
                  ),
                ),
            ],
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : AppSpacing.m),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: isCurrent ? FontWeight.w700 : FontWeight.w600,
                      color: isError
                          ? AppColors.error
                          : (isCompleted || isCurrent
                                ? AppColors.textPrimary
                                : AppColors.textSecondary),
                    ),
                  ),
                  if (date != null) ...[
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      DateFormat('MMM dd, yyyy • hh:mm a').format(date),
                      style: AppTypography.caption,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
