import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_spacing.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/core/widgets/states/app_empty_state.dart';
import 'package:twin_ar/features/admin/orders_payments/models/admin_orders_payments_mode.dart';
import 'package:twin_ar/features/admin/orders_payments/viewmodels/admin_orders_viewmodel.dart';
import 'package:twin_ar/features/admin/orders_payments/viewmodels/admin_payments_viewmodel.dart';
import 'package:twin_ar/features/admin/orders_payments/widgets/admin_order_card.dart';
import 'package:twin_ar/features/admin/orders_payments/widgets/admin_orders_filter_bar.dart';
import 'package:twin_ar/features/admin/orders_payments/widgets/admin_payment_card.dart';
import 'package:twin_ar/features/admin/orders_payments/widgets/admin_payments_filter_bar.dart';
import 'package:twin_ar/features/admin/views/admin_shell.dart';

class AdminOrdersView extends StatelessWidget {
  const AdminOrdersView({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<AdminOrdersViewModel>(
          create: (context) =>
              AdminOrdersViewModel(context.read<CommerceDatabase>()),
        ),
        ChangeNotifierProvider<AdminPaymentsViewModel>(
          create: (context) =>
              AdminPaymentsViewModel(context.read<CommerceDatabase>()),
        ),
      ],
      child: const _AdminOrdersViewContent(),
    );
  }
}

class _AdminOrdersViewContent extends StatefulWidget {
  const _AdminOrdersViewContent();

  @override
  State<_AdminOrdersViewContent> createState() =>
      _AdminOrdersViewContentState();
}

class _AdminOrdersViewContentState extends State<_AdminOrdersViewContent> {
  final TextEditingController _ordersSearchController = TextEditingController();
  final TextEditingController _paymentsSearchController =
      TextEditingController();
  AdminOrdersPaymentsMode _mode = AdminOrdersPaymentsMode.orders;

  @override
  void dispose() {
    _ordersSearchController.dispose();
    _paymentsSearchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ordersViewModel = context.watch<AdminOrdersViewModel>();
    final paymentsViewModel = context.watch<AdminPaymentsViewModel>();
    final isOrdersMode = _mode == AdminOrdersPaymentsMode.orders;
    final orders = ordersViewModel.filteredOrders;
    final payments = paymentsViewModel.filteredPayments;

    return AdminShell(
      currentIndex: 3,
      title: 'Orders',
      showGreeting: false,
      // A single CustomScrollView (header + list/empty-state as slivers),
      // matching the pattern established for Inventory, so a squeezed
      // viewport (e.g. keyboard open while searching) scrolls instead of
      // ever forcing a fixed section to overflow.
      child: CustomScrollView(
        key: const Key('admin_orders_scroll_view'),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.m,
                AppSpacing.m,
                AppSpacing.m,
                AppSpacing.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Orders & Payments', style: AppTypography.title),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    isOrdersMode
                        ? 'Manage customer orders and payment activity'
                        : 'Track transactions and payment status',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  _buildModeSelector(isOrdersMode),
                  if (isOrdersMode) ...[
                    const SizedBox(height: AppSpacing.m),
                    AdminOrdersFilterBar(
                      searchController: _ordersSearchController,
                      onSearchChanged: ordersViewModel.setSearchQuery,
                      statusFilter: ordersViewModel.statusFilter,
                      onStatusFilterChanged: ordersViewModel.setStatusFilter,
                      paymentStatusFilter: ordersViewModel.paymentStatusFilter,
                      onPaymentStatusFilterChanged:
                          ordersViewModel.setPaymentStatusFilter,
                    ),
                  ] else ...[
                    const SizedBox(height: AppSpacing.m),
                    AdminPaymentsFilterBar(
                      searchController: _paymentsSearchController,
                      onSearchChanged: paymentsViewModel.setSearchQuery,
                      statusFilter: paymentsViewModel.statusFilter,
                      onStatusFilterChanged: paymentsViewModel.setStatusFilter,
                    ),
                    const SizedBox(height: AppSpacing.m),
                    _buildPaymentsSummary(paymentsViewModel),
                  ],
                ],
              ),
            ),
          ),
          if (isOrdersMode)
            ..._buildOrdersSlivers(context, ordersViewModel, orders)
          else
            ..._buildPaymentsSlivers(paymentsViewModel, payments),
        ],
      ),
    );
  }

  List<Widget> _buildOrdersSlivers(
    BuildContext context,
    AdminOrdersViewModel viewModel,
    List<OrderModel> orders,
  ) {
    if (viewModel.totalOrdersCount == 0) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: const AppEmptyState(
            title: 'No orders yet',
            message: 'Orders will appear here once a customer checks out.',
            icon: Icons.receipt_long_outlined,
          ),
        ),
      ];
    }
    if (orders.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: const AppEmptyState(
            title: 'No orders found',
            message: 'Try a different search term or adjust your filters.',
            icon: Icons.search_off,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          0,
          AppSpacing.m,
          AppSpacing.m,
        ),
        sliver: SliverList.builder(
          itemCount: orders.length,
          itemBuilder: (context, index) {
            final order = orders[index];
            return AdminOrderCard(
              key: ValueKey(order.id),
              order: order,
              onViewDetails: () => Navigator.pushNamed(
                context,
                RouteNames.adminOrderDetail,
                arguments: order.id,
              ),
            );
          },
        ),
      ),
    ];
  }

  List<Widget> _buildPaymentsSlivers(
    AdminPaymentsViewModel viewModel,
    List<PaymentRecord> payments,
  ) {
    if (viewModel.totalPaymentsCount == 0) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: const AppEmptyState(
            title: 'No payments yet',
            message: 'Payments will appear here once a customer checks out.',
            icon: Icons.payments_outlined,
          ),
        ),
      ];
    }
    if (payments.isEmpty) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: const AppEmptyState(
            title: 'No payments found',
            message: 'Try a different search term or adjust your filters.',
            icon: Icons.search_off,
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          0,
          AppSpacing.m,
          AppSpacing.m,
        ),
        sliver: SliverList.builder(
          itemCount: payments.length,
          itemBuilder: (context, index) {
            final payment = payments[index];
            return AdminPaymentCard(
              key: ValueKey(payment.paymentId),
              payment: payment,
              linkedOrder: viewModel.linkedOrderFor(payment),
            );
          },
        ),
      ),
    ];
  }

  Widget _buildPaymentsSummary(AdminPaymentsViewModel viewModel) {
    return Wrap(
      spacing: AppSpacing.m,
      runSpacing: AppSpacing.xs,
      children: [
        _buildSummaryTile(
          'Total Payments',
          viewModel.totalPaymentsCount,
          Icons.receipt_long_outlined,
          AppColors.primaryDark,
        ),
        _buildSummaryTile(
          'Paid',
          viewModel.paidCount,
          Icons.check_circle_outline,
          AppColors.success,
        ),
        _buildSummaryTile(
          'Pending',
          viewModel.pendingCount,
          Icons.schedule,
          AppColors.warning,
        ),
        _buildSummaryTile(
          'Failed',
          viewModel.failedCount,
          Icons.cancel_outlined,
          AppColors.error,
        ),
      ],
    );
  }

  Widget _buildSummaryTile(
    String label,
    int count,
    IconData icon,
    Color color,
  ) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: AppSpacing.xxs),
        Text(
          '$label: ',
          style: AppTypography.caption.copyWith(color: AppColors.textSecondary),
        ),
        Text(
          '$count',
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.w700,
            color: AppColors.textPrimary,
          ),
        ),
      ],
    );
  }

  Widget _buildModeSelector(bool isOrdersMode) {
    return Row(
      children: [
        Expanded(
          child: _buildModeButton(
            'Orders',
            isOrdersMode,
            () => setState(() => _mode = AdminOrdersPaymentsMode.orders),
          ),
        ),
        const SizedBox(width: AppSpacing.s),
        Expanded(
          child: _buildModeButton(
            'Payments',
            !isOrdersMode,
            () => setState(() => _mode = AdminOrdersPaymentsMode.payments),
          ),
        ),
      ],
    );
  }

  Widget _buildModeButton(String title, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      key: Key('admin_orders_mode_${title.toLowerCase()}'),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.neutralLight,
          ),
        ),
        alignment: Alignment.center,
        child: Text(
          title,
          style: AppTypography.bodyMedium.copyWith(
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? AppColors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
