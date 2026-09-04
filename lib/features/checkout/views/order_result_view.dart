import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';

import '../../../app/routes/route_names.dart';
import '../../../app/viewmodels/customer_order_state.dart';
import '../../../core/models/order/order_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/utils/order_id_formatter.dart';

class OrderResultView extends StatelessWidget {
  final String orderId;

  const OrderResultView({super.key, required this.orderId});

  @override
  Widget build(BuildContext context) {
    final orderState = context.watch<CustomerOrderState>();
    final order = orderState.getOrderById(orderId);

    if (order == null) {
      return Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          backgroundColor: AppColors.white,
          elevation: 0,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
            onPressed: () {
              Navigator.pushNamedAndRemoveUntil(
                context,
                RouteNames.home,
                (route) => false,
              );
            },
          ),
          title: Text('Order Not Found', style: AppTypography.headingMedium),
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'Sorry, we could not find this order.',
                style: AppTypography.bodyLarge,
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () {
                  Navigator.pushNamedAndRemoveUntil(
                    context,
                    RouteNames.home,
                    (route) => false,
                  );
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                ),
                child: const Text('Return Home'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Success Illustration
                    Center(
                      child: Image.asset(
                        'assets/images/order/order_success.png',
                        height: 160,
                        fit: BoxFit.contain,
                      ),
                    ),
                    const SizedBox(height: 24),

                    // Success Text
                    Text(
                      'Order Placed Successfully',
                      textAlign: TextAlign.center,
                      style: AppTypography.headingMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Your order has been placed successfully. For more details, check All My Orders page under Profile tab',
                      textAlign: TextAlign.center,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Order Summary Card
                    _buildOrderSummaryCard(order),
                    const SizedBox(height: 32),

                    // Continue Shopping
                    SizedBox(
                      height: 50,
                      child: ElevatedButton(
                        onPressed: () => _returnHome(context),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: AppColors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          elevation: 0,
                        ),
                        child: Text(
                          'Continue Shopping',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.white,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Track Order
                    SizedBox(
                      height: 50,
                      child: OutlinedButton(
                        onPressed: () {
                          Navigator.pushNamed(
                            context,
                            RouteNames.orderDetail,
                            arguments: orderId,
                          );
                        },
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                        child: Text(
                          'Track Order',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _returnHome(BuildContext context) {
    Navigator.pushNamedAndRemoveUntil(
      context,
      RouteNames.home,
      (route) => false,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      color: AppColors
          .background, // Match background to keep clean look if target uses it
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => _returnHome(context),
            child: const Icon(Icons.arrow_back, color: AppColors.textPrimary),
          ),
          const SizedBox(width: 16),
          Text(
            '',
            style: AppTypography.headingMedium,
          ), // Blank title if not specified
        ],
      ),
    );
  }

  Widget _buildOrderSummaryCard(OrderModel order) {
    final format = NumberFormat.decimalPattern('en_IN');
    final formattedTotal = 'Rs ${format.format(order.total)}/-';

    final DateFormat formatter = DateFormat('EEE, d MMM');
    final String dateRange =
        '${formatter.format(order.estimatedDeliveryStart)} - ${formatter.format(order.estimatedDeliveryEnd)}';

    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutralLight),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSummaryRow(
            'Order ID',
            OrderIdFormatter.short(order.id),
            valueColor: AppColors.textPrimary,
          ),
          const SizedBox(height: 12),
          _buildSummaryRow('Amount', formattedTotal, isBold: true),
          const SizedBox(height: 12),
          _buildSummaryRow('Payment Method', 'Stripe / Card'),
          const SizedBox(height: 12),
          _buildSummaryRow(
            'Payment Status',
            'Paid',
            valueColor: AppColors.success, // Assuming a green text status
            isBold: true,
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: AppColors.neutralMediumLight, height: 1),
          ),
          Text(
            'Delivery Address',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            order.deliveryAddress.fullName,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            order.deliveryAddress.formattedAddressLines.join(', '),
            style: AppTypography.bodyMedium,
          ),
          const SizedBox(height: 16),
          Text(
            'Estimated Delivery',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            dateRange,
            style: AppTypography.bodyMedium.copyWith(
              fontWeight: FontWeight.w600,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(
    String label,
    String value, {
    Color? valueColor,
    bool isBold = false,
  }) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(width: 12),
        Flexible(
          child: Text(
            value,
            style: AppTypography.bodyMedium.copyWith(
              color: valueColor ?? AppColors.textPrimary,
              fontWeight: isBold ? FontWeight.w600 : FontWeight.w400,
            ),
            textAlign: TextAlign.end,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}
