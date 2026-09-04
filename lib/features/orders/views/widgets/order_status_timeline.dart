import 'package:flutter/material.dart';
import '../../../../core/models/order/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import 'package:intl/intl.dart';

class OrderStatusTimeline extends StatelessWidget {
  final OrderStatus currentStatus;
  final DateTime orderDate;

  const OrderStatusTimeline({
    super.key,
    required this.currentStatus,
    required this.orderDate,
  });

  @override
  Widget build(BuildContext context) {
    if (currentStatus == OrderStatus.cancelled) {
      return _buildCancelledTimeline();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStep(
              context: context,
              title: 'Pending',
              date: orderDate,
              icon: Icons.shopping_cart_outlined,
              isCompleted: _isCompleted(OrderStatus.pending),
              isCurrent: currentStatus == OrderStatus.pending,
              isFirst: true,
              isLast: false,
            ),
            _buildConnector(isCompleted: _isCompleted(OrderStatus.pending)),
            _buildStep(
              context: context,
              title: 'Confirmed',
              date: null,
              icon: Icons.inventory_2_outlined,
              isCompleted: _isCompleted(OrderStatus.confirmed),
              isCurrent: currentStatus == OrderStatus.confirmed,
              isFirst: false,
              isLast: false,
            ),
            _buildConnector(isCompleted: _isCompleted(OrderStatus.confirmed)),
            _buildStep(
              context: context,
              title: 'Shipped',
              date: null,
              icon: Icons.local_shipping_outlined,
              isCompleted: _isCompleted(OrderStatus.shipped),
              isCurrent: currentStatus == OrderStatus.shipped,
              isFirst: false,
              isLast: false,
            ),
            _buildConnector(isCompleted: _isCompleted(OrderStatus.shipped)),
            _buildStep(
              context: context,
              title: 'Delivered',
              date: null,
              icon: Icons.home_outlined,
              isCompleted: _isCompleted(OrderStatus.delivered),
              isCurrent: currentStatus == OrderStatus.delivered,
              isFirst: false,
              isLast: true,
            ),
          ],
        );
      },
    );
  }

  Widget _buildCancelledTimeline() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildStep(
          context: null,
          title: 'Pending',
          date: orderDate,
          icon: Icons.shopping_cart_outlined,
          isCompleted: true,
          isCurrent: false,
          isFirst: true,
          isLast: false,
        ),
        _buildConnector(isCompleted: true, isError: true),
        _buildStep(
          context: null,
          title: 'Cancelled',
          date: null,
          icon: Icons.cancel_outlined,
          isCompleted: true,
          isCurrent: true,
          isFirst: false,
          isLast: true,
          isError: true,
        ),
        const Spacer(),
        const Spacer(),
        const Spacer(),
        const Spacer(),
      ],
    );
  }

  bool _isCompleted(OrderStatus step) {
    final values = [
      OrderStatus.pending,
      OrderStatus.confirmed,
      OrderStatus.shipped,
      OrderStatus.delivered,
    ];
    return values.indexOf(currentStatus) > values.indexOf(step);
  }

  Widget _buildConnector({required bool isCompleted, bool isError = false}) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(top: 24),
        height: 2,
        color: isError
            ? AppColors.error
            : (isCompleted ? AppColors.primary : AppColors.neutralLight),
      ),
    );
  }

  Widget _buildStep({
    BuildContext? context,
    required String title,
    required DateTime? date,
    required IconData icon,
    required bool isCompleted,
    required bool isCurrent,
    required bool isFirst,
    required bool isLast,
    bool isError = false,
  }) {
    final color = isError
        ? AppColors.error
        : (isCompleted || isCurrent
              ? AppColors.primary
              : AppColors.textSecondary);

    final bgColor = isCompleted ? color : AppColors.background;

    final iconColor = isCompleted ? AppColors.background : color;

    final borderColor = isCompleted || isCurrent
        ? color
        : AppColors.neutralLight;

    return Flexible(
      flex: 0,
      fit: FlexFit.loose,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: bgColor,
              border: Border.all(color: borderColor, width: 2),
            ),
            child: Icon(icon, color: iconColor, size: 24),
          ),
          const SizedBox(height: 8),
          Text(
            title,
            style: AppTypography.bodySmall.copyWith(
              fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w500,
              color: isError
                  ? AppColors.error
                  : (isCurrent || isCompleted
                        ? AppColors.textPrimary
                        : AppColors.textSecondary),
              fontSize: 9,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
          ),
          if (date != null)
            Text(
              DateFormat('MMM dd, hh:mm a').format(date),
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 9,
              ),
              textAlign: TextAlign.center,
            ),
        ],
      ),
    );
  }
}
