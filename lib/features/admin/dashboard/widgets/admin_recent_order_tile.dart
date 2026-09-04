import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../../core/models/order/order_item_model.dart';
import '../../../../core/models/order/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/order_id_formatter.dart';
import '../../../../core/widgets/product_image_view.dart';

class AdminRecentOrderTile extends StatelessWidget {
  final OrderModel order;
  final VoidCallback? onTap;

  const AdminRecentOrderTile({super.key, required this.order, this.onTap});

  @override
  Widget build(BuildContext context) {
    final dateFormat = DateFormat('MMM dd, yyyy • hh:mm a');
    final formattedDate = dateFormat.format(order.orderDate);
    final totalAmount = CurrencyFormatter.format(order.total);

    // We get the image from the first item
    final OrderItemModel? firstItem = order.items.isNotEmpty
        ? order.items.first
        : null;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: InkWell(
        onTap: onTap,
        borderRadius: AppRadii.largeBorder,
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.m),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: AppRadii.largeBorder,
            border: Border.all(color: AppColors.primary),
          ),
          child: Row(
            children: [
              // Image
              Container(
                width: 48.0,
                height: 48.0,
                decoration: BoxDecoration(
                  color: AppColors.background,
                  borderRadius: AppRadii.smallBorder,
                ),
                clipBehavior: Clip.antiAlias,
                child: firstItem != null
                    ? ProductImageView(imageRef: firstItem.image)
                    : const Icon(
                        Icons.shopping_bag_outlined,
                        color: AppColors.textSecondary,
                      ),
              ),
              const SizedBox(width: AppSpacing.m),

              // Middle section (ID + Date)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      OrderIdFormatter.short(order.id),
                      style: AppTypography.bodySmall.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      formattedDate,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                        fontSize: 10,
                      ),
                      maxLines: 1,
                    ),
                  ],
                ),
              ),

              const SizedBox(width: AppSpacing.s),
              // Status Tag
              _buildStatusTag(order.orderStatus),

              const SizedBox(width: AppSpacing.m),

              // Amount and Chevron
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    totalAmount,
                    style: AppTypography.bodySmall.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.chevron_right,
                    size: 16,
                    color: AppColors.textSecondary,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStatusTag(OrderStatus status) {
    Color bgColor;
    Color textColor;

    switch (status) {
      case OrderStatus.pending:
        bgColor = const Color(0xFFFFF7E6); // Light orange
        textColor = const Color(0xFFD97706); // Orange
        break;
      case OrderStatus.confirmed:
      case OrderStatus.shipped:
      case OrderStatus.delivered:
        bgColor = const Color(0xFFECFDF5); // Light green
        textColor = const Color(0xFF059669); // Green
        break;
      case OrderStatus.cancelled:
        bgColor = const Color(0xFFFEF2F2); // Light red
        textColor = const Color(0xFFDC2626); // Red
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: AppRadii.largeBorder,
        border: Border.all(color: textColor.withValues(alpha: 0.3)),
      ),
      child: Text(
        status.displayName,
        style: AppTypography.bodySmall.copyWith(
          color: textColor,
          fontWeight: FontWeight.w500,
          fontSize: 9, // Reduced font size
        ),
      ),
    );
  }
}
