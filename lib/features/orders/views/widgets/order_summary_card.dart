import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/order/order_item_model.dart';
import '../../../../core/models/order/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/order_id_formatter.dart';
import '../../../../core/widgets/product_image_view.dart';
import '../../../../app/routes/route_names.dart';

/// Display-only: shortens the id (see [OrderIdFormatter]), then applies
/// this widget's pre-existing '#'-prefix fallback for any id that somehow
/// lacks one - unchanged behavior for that edge case, just composed with
/// the new shortening.
String _displayOrderId(String id) {
  final display = OrderIdFormatter.short(id);
  return display.startsWith('#') ? display : '#$display';
}

class OrderSummaryCard extends StatelessWidget {
  final OrderModel order;

  const OrderSummaryCard({super.key, required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neutralLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildThumbnail(),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _buildHeaderRow(),
                  const SizedBox(height: 12),
                  _buildMiddleRows(),
                  const SizedBox(height: 12),
                  const Divider(color: AppColors.neutralLight, height: 1),
                  const SizedBox(height: 12),
                  _buildFooterRows(context),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail() {
    OrderItemModel? firstItem = order.items.isNotEmpty
        ? order.items.first
        : null;

    return Container(
      width: 90,
      decoration: BoxDecoration(
        color: AppColors.neutralLight,
        borderRadius: BorderRadius.circular(12),
      ),
      clipBehavior: Clip.antiAlias,
      child: firstItem != null && firstItem.imagePath.isNotEmpty
          ? ProductImageView(imageRef: firstItem.image, fit: BoxFit.cover)
          : const Icon(
              Icons.inventory_2_outlined,
              color: AppColors.textSecondary,
            ),
    );
  }

  Widget _buildHeaderRow() {
    final DateFormat formatter = DateFormat('MMM d, yyyy');
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Order ID',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            Row(
              children: [
                const Icon(
                  Icons.calendar_today_outlined,
                  size: 12,
                  color: AppColors.textSecondary,
                ),
                const SizedBox(width: 4),
                Text(
                  formatter.format(order.orderDate),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 2),
        Text(
          _displayOrderId(order.id),
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: FontWeight.w600,
            fontSize: 13,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }

  Widget _buildMiddleRows() {
    final format = NumberFormat.currency(
      locale: 'en_IN',
      symbol: 'Rs ',
      decimalDigits: 0,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Total Amount',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  format.format(order.total),
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  'Payment Method',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    fontSize: 11,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  order.paymentMethod.displayName,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 10),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Payment Status',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(height: 4),
            _buildPaymentStatusBadge(),
          ],
        ),
      ],
    );
  }

  Widget _buildPaymentStatusBadge() {
    Color bgColor = AppColors.success.withValues(alpha: 0.1);
    Color textColor = AppColors.success;
    IconData icon = Icons.check_circle_outline;

    if (order.paymentStatus == PaymentStatus.failed) {
      bgColor = AppColors.error.withValues(alpha: 0.1);
      textColor = AppColors.error;
      icon = Icons.cancel_outlined;
    } else if (order.paymentStatus == PaymentStatus.pending) {
      bgColor = AppColors.warning.withValues(alpha: 0.1);
      textColor = AppColors.warning;
      icon = Icons.access_time;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8), // Match smaller badge style
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            order.paymentStatus.displayName,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(width: 4),
          Icon(icon, size: 12, color: textColor),
        ],
      ),
    );
  }

  Widget _buildFooterRows(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              'Order Status',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
                fontSize: 11,
              ),
            ),
            const SizedBox(width: 8),
            _buildOrderStatusBadge(),
          ],
        ),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                RouteNames.orderDetail,
                arguments: order.id,
              );
            },
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text(
                    'View Details',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 4),
                  const Icon(
                    Icons.chevron_right,
                    size: 14,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildOrderStatusBadge() {
    Color bgColor;
    Color textColor;
    IconData icon;

    switch (order.orderStatus) {
      case OrderStatus.pending:
        bgColor = AppColors.warning.withValues(alpha: 0.1);
        textColor = AppColors.warning;
        icon = Icons.access_time;
        break;
      case OrderStatus.confirmed:
        bgColor = Colors.blue.withValues(alpha: 0.1);
        textColor = Colors.blue;
        icon = Icons.check_circle_outline;
        break;
      case OrderStatus.shipped:
        bgColor = Colors.deepPurple.withValues(alpha: 0.1);
        textColor = Colors.deepPurple;
        icon = Icons.local_shipping_outlined;
        break;
      case OrderStatus.delivered:
        bgColor = AppColors.success.withValues(alpha: 0.1);
        textColor = AppColors.success;
        icon = Icons.check_circle_outline;
        break;
      case OrderStatus.cancelled:
        bgColor = AppColors.error.withValues(alpha: 0.1);
        textColor = AppColors.error;
        icon = Icons.cancel_outlined;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: textColor),
          const SizedBox(width: 4),
          Text(
            order.orderStatus.displayName,
            style: TextStyle(
              color: textColor,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
