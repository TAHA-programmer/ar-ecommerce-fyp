import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/models/order/order_item_model.dart';
import '../../../../core/models/order/order_model.dart';
import '../../../../core/models/order/payment_record.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/currency_formatter.dart';
import '../../../../core/utils/order_id_formatter.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/widgets/product_image_view.dart';
import '../../../../core/widgets/states/app_empty_state.dart';
import '../../views/admin_shell.dart';
import '../viewmodels/admin_order_detail_viewmodel.dart';
import '../widgets/admin_order_status_selector.dart';
import '../widgets/admin_order_status_timeline.dart';

class AdminOrderDetailView extends StatelessWidget {
  const AdminOrderDetailView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminOrderDetailViewModel>();

    return AdminShell(
      currentIndex: 3,
      title: 'Orders',
      showGreeting: false,
      child: Column(
        children: [
          _buildTitleRow(context),
          Expanded(
            child: viewModel.isNotFound || viewModel.order == null
                ? const AppEmptyState(
                    title: 'Order not found',
                    message:
                        'This order may have been removed or the link is no longer valid.',
                    icon: Icons.receipt_long_outlined,
                  )
                : _buildContent(context, viewModel, viewModel.order!),
          ),
        ],
      ),
    );
  }

  Widget _buildTitleRow(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.s,
        AppSpacing.m,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('admin_order_detail_back_button'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text('Order Details', style: AppTypography.title),
        ],
      ),
    );
  }

  Widget _buildContent(
    BuildContext context,
    AdminOrderDetailViewModel viewModel,
    OrderModel order,
  ) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        0,
        AppSpacing.m,
        AppSpacing.xl,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _OrderSummaryCard(order: order),
          const SizedBox(height: AppSpacing.m),
          _ResponsivePair(
            left: _CustomerInformationCard(order: order),
            right: _DeliveryAddressCard(order: order),
          ),
          const SizedBox(height: AppSpacing.m),
          _OrderedProductsCard(order: order),
          const SizedBox(height: AppSpacing.m),
          _ResponsivePair(
            left: _PriceSummaryCard(order: order),
            right: _PaymentInformationCard(
              order: order,
              linkedPayment: viewModel.linkedPayment,
            ),
          ),
          const SizedBox(height: AppSpacing.m),
          _ResponsivePair(
            left: _CurrentStatusCard(order: order),
            right: _TimelineCard(order: order),
          ),
          const SizedBox(height: AppSpacing.m),
          _UpdateStatusCard(viewModel: viewModel),
        ],
      ),
    );
  }
}

// --- Shared visual helpers ---

BoxDecoration _cardDecoration() => BoxDecoration(
  color: AppColors.surface,
  borderRadius: AppRadii.largeBorder,
  border: Border.all(color: AppColors.primary),
);

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

class _SectionLabel extends StatelessWidget {
  final String text;
  final IconData icon;

  const _SectionLabel({required this.text, required this.icon});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 16, color: AppColors.primaryDark),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          text,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.primaryDark,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const _StatusBadge({required this.label, required this.color, this.icon});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadii.smallBorder,
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 12, color: color),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: AppTypography.bodySmall.copyWith(
              color: color,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Stacks two cards on narrow phone widths, places them side by side once
/// there is genuinely enough room. Threshold chosen well above typical
/// phone widths (tested down to 360px) so this never overflows.
class _ResponsivePair extends StatelessWidget {
  final Widget left;
  final Widget right;

  const _ResponsivePair({required this.left, required this.right});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 560) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: left),
              const SizedBox(width: AppSpacing.m),
              Expanded(child: right),
            ],
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            left,
            const SizedBox(height: AppSpacing.m),
            right,
          ],
        );
      },
    );
  }
}

// --- A. Order Summary Card ---

class _OrderSummaryCard extends StatelessWidget {
  final OrderModel order;

  const _OrderSummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final style = _orderStatusStyle(order.orderStatus);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: Row(
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
                  OrderIdFormatter.short(order.id),
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w700,
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
                        DateFormat(
                          'MMM dd, yyyy • hh:mm a',
                        ).format(order.orderDate),
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
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                CurrencyFormatter.format(order.total),
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Wrap(
                alignment: WrapAlignment.end,
                spacing: AppSpacing.xxs,
                runSpacing: AppSpacing.xxs,
                children: [
                  _StatusBadge(
                    label: order.paymentMethod.displayName,
                    color: AppColors.primaryDark,
                  ),
                  _StatusBadge(
                    label: order.paymentStatus.displayName,
                    color: _paymentStatusColor(order.paymentStatus),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// --- B. Customer Information Card ---

class _CustomerInformationCard extends StatelessWidget {
  final OrderModel order;

  const _CustomerInformationCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final address = order.deliveryAddress;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(
            text: 'Customer Information',
            icon: Icons.person_outline,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            address.fullName,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            address.phoneNumber,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

// --- C. Delivery Address Card ---

class _DeliveryAddressCard extends StatelessWidget {
  final OrderModel order;

  const _DeliveryAddressCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final address = order.deliveryAddress;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(
            text: 'Delivery Address',
            icon: Icons.location_on_outlined,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            address.fullName,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          for (final line in address.formattedAddressLines)
            Text(
              line,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
        ],
      ),
    );
  }
}

// --- D. Ordered Products Card ---

class _OrderedProductsCard extends StatelessWidget {
  final OrderModel order;

  const _OrderedProductsCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Ordered Products (${order.items.length})',
            style: AppTypography.title.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.s),
          for (int i = 0; i < order.items.length; i++) ...[
            if (i > 0) ...[
              const SizedBox(height: AppSpacing.s),
              const Divider(color: AppColors.neutralLight, height: 1),
              const SizedBox(height: AppSpacing.s),
            ],
            _buildItemRow(order.items[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildItemRow(OrderItemModel item) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ClipRRect(
          borderRadius: AppRadii.smallBorder,
          child: ProductImageView(
            imageRef: item.image,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                item.productName,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (item.selectedSize != null || item.selectedColor != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  [
                    if (item.selectedSize != null) 'Size: ${item.selectedSize}',
                    if (item.selectedColor != null)
                      'Color: ${item.selectedColor}',
                  ].join(' • '),
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
              const SizedBox(height: AppSpacing.xxs),
              Text(
                'Qty: ${item.quantity}',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: AppSpacing.xs),
        Text(
          CurrencyFormatter.format(item.lineTotal),
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}

// --- E. Price Summary Card ---

class _PriceSummaryCard extends StatelessWidget {
  final OrderModel order;

  const _PriceSummaryCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Price Summary',
            style: AppTypography.title.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.s),
          _buildRow('Subtotal', CurrencyFormatter.format(order.subtotal)),
          const SizedBox(height: AppSpacing.xs),
          _buildRow(
            'Delivery Fee',
            CurrencyFormatter.format(order.deliveryFee),
          ),
          const SizedBox(height: AppSpacing.xs),
          _buildRow(
            'Discount',
            '-${CurrencyFormatter.format(order.discount)}',
            valueColor: AppColors.primary,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: AppSpacing.s),
            child: Divider(color: AppColors.neutralLight, height: 1),
          ),
          _buildRow(
            'Total',
            CurrencyFormatter.format(order.total),
            isTotal: true,
          ),
        ],
      ),
    );
  }

  Widget _buildRow(
    String label,
    String value, {
    bool isTotal = false,
    Color? valueColor,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: isTotal
              ? AppTypography.title.copyWith(fontSize: 14)
              : AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
        ),
        Text(
          value,
          style:
              (isTotal
                      ? AppTypography.title.copyWith(fontSize: 14)
                      : AppTypography.bodyMedium)
                  .copyWith(
                    fontWeight: FontWeight.w700,
                    color: isTotal
                        ? AppColors.primary
                        : (valueColor ?? AppColors.textPrimary),
                  ),
        ),
      ],
    );
  }
}

// --- F. Payment Information Card ---

class _PaymentInformationCard extends StatelessWidget {
  final OrderModel order;
  final PaymentRecord? linkedPayment;

  const _PaymentInformationCard({
    required this.order,
    required this.linkedPayment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _SectionLabel(
            text: 'Payment Information',
            icon: Icons.payment_outlined,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Payment Method',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            order.paymentMethod.displayName,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Payment Status',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          _StatusBadge(
            label: order.paymentStatus.displayName,
            color: _paymentStatusColor(order.paymentStatus),
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Transaction ID',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            linkedPayment != null
                ? OrderIdFormatter.short(linkedPayment!.paymentId)
                : '—',
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

// --- G. Current Order Status + Timeline Cards ---

class _CurrentStatusCard extends StatelessWidget {
  final OrderModel order;

  const _CurrentStatusCard({required this.order});

  @override
  Widget build(BuildContext context) {
    final style = _orderStatusStyle(order.orderStatus);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Order Status',
            style: AppTypography.title.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.s),
          _StatusBadge(
            label: order.orderStatus.displayName,
            color: style.color,
            icon: style.icon,
          ),
        ],
      ),
    );
  }
}

class _TimelineCard extends StatelessWidget {
  final OrderModel order;

  const _TimelineCard({required this.order});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Order Timeline',
            style: AppTypography.title.copyWith(fontSize: 14),
          ),
          const SizedBox(height: AppSpacing.m),
          AdminOrderStatusTimeline(
            currentStatus: order.orderStatus,
            orderDate: order.orderDate,
          ),
        ],
      ),
    );
  }
}

// --- H. Update Order Status Card ---

class _UpdateStatusCard extends StatelessWidget {
  final AdminOrderDetailViewModel viewModel;

  const _UpdateStatusCard({required this.viewModel});

  void _handleUpdate(BuildContext context) {
    if (viewModel.requiresConfirmation) {
      _showConfirmationDialog(context);
    } else {
      _commitAndNotify(context);
    }
  }

  Future<void> _commitAndNotify(BuildContext context) async {
    final target = viewModel.stagedStatus;
    final success = await viewModel.commitStatus();
    if (!context.mounted) return;
    if (success) {
      AppToast.success(
        context,
        'Order status updated to ${target?.displayName}',
      );
    } else {
      AppToast.error(
        context,
        'Failed to update order status. Please try again.',
      );
    }
  }

  void _showConfirmationDialog(BuildContext context) {
    final target = viewModel.stagedStatus!;
    final isCancel = target == OrderStatus.cancelled;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Mark order as ${target.displayName}?'),
        content: Text(
          'This will change the order status to ${target.displayName}. '
          'The change reflects immediately across Admin and Customer surfaces.',
        ),
        shape: RoundedRectangleBorder(borderRadius: AppRadii.largeBorder),
        actions: [
          TextButton(
            key: const Key('admin_order_status_confirm_cancel'),
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(
              'Keep Editing',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            key: const Key('admin_order_status_confirm_apply'),
            onPressed: () {
              Navigator.of(dialogContext).pop();
              _commitAndNotify(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: isCancel ? AppColors.error : AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final order = viewModel.order!;
    return Container(
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: _cardDecoration(),
      child: AdminOrderStatusSelector(
        stagedStatus: viewModel.stagedStatus ?? order.orderStatus,
        isSelectable: viewModel.canTransitionTo,
        onSelect: viewModel.stageStatus,
        hasPendingChange: viewModel.hasPendingChange,
        onUpdate: () => _handleUpdate(context),
        onClose: () => Navigator.of(context).pop(),
      ),
    );
  }
}
