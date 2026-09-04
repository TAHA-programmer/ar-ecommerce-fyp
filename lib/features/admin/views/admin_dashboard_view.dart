import 'package:twin_ar/app/routes/route_names.dart';
import 'package:flutter/material.dart';

import 'package:provider/provider.dart';
import 'package:twin_ar/features/admin/views/admin_shell.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_spacing.dart';

import 'package:twin_ar/core/utils/currency_formatter.dart';

import '../dashboard/viewmodels/admin_dashboard_viewmodel.dart';
import '../dashboard/widgets/admin_metric_card.dart';
import '../dashboard/widgets/admin_section_header.dart';
import '../dashboard/widgets/admin_recent_order_tile.dart';
import '../dashboard/widgets/admin_low_stock_tile.dart';
import '../dashboard/widgets/admin_recent_product_card.dart';
import '../dashboard/widgets/admin_payment_summary_card.dart';

class AdminDashboardView extends StatelessWidget {
  const AdminDashboardView({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminShell(
      currentIndex: 0,
      title: 'Admin',
      showGreeting: true,
      child: Consumer<AdminDashboardViewModel>(
        builder: (context, viewModel, child) {
          return SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildMetricsGrid(viewModel),
                _buildTotalRevenueCard(viewModel),
                _buildRecentOrders(context, viewModel),
                _buildLowStockProducts(context, viewModel),
                _buildRecentlyAddedProducts(context, viewModel),
                _buildPaymentSummary(context, viewModel),
                const SizedBox(height: AppSpacing.xxl), // Bottom padding
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricsGrid(AdminDashboardViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final spacing = AppSpacing.s;
          // Calculate item width based on available space and spacing
          final itemWidth = constraints.maxWidth;

          return Wrap(
            spacing: spacing,
            runSpacing: spacing,
            children: [
              SizedBox(
                width: itemWidth,
                child: AdminMetricCard(
                  icon: Icons.shopping_bag,
                  iconBackgroundColor: const Color(0xFFF4F8E5), // Light primary
                  iconColor: AppColors.primary,
                  label: 'Total Products',
                  value: viewModel.totalProducts.toString(),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: AdminMetricCard(
                  icon: Icons.shopping_cart_outlined,
                  iconBackgroundColor: const Color(0xFFF4F8E5),
                  iconColor: AppColors.primary,
                  label: 'Total Orders',
                  value: viewModel.totalOrders.toString(),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: AdminMetricCard(
                  icon: Icons.schedule,
                  iconBackgroundColor: const Color(0xFFF4F8E5),
                  iconColor: AppColors.primary,
                  label: 'Pending Orders',
                  value: viewModel.pendingOrdersCount.toString(),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: AdminMetricCard(
                  icon: Icons.warning_amber_rounded,
                  iconBackgroundColor: const Color(0xFFF4F8E5),
                  iconColor: AppColors.primary,
                  label: 'Low-Stock Products',
                  value: viewModel.lowStockProductsCount.toString(),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: AdminMetricCard(
                  icon: Icons.check_circle_outline,
                  iconBackgroundColor: const Color(0xFFF4F8E5),
                  iconColor: AppColors.primary,
                  label: 'Successful Payments',
                  value: viewModel.successfulPaymentsCount.toString(),
                ),
              ),
              SizedBox(
                width: itemWidth,
                child: AdminMetricCard(
                  icon: Icons.cancel_outlined,
                  iconBackgroundColor: const Color(0xFFF4F8E5),
                  iconColor: AppColors.primary,
                  label: 'Failed Payments',
                  value: viewModel.failedPaymentsCount.toString(),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTotalRevenueCard(AdminDashboardViewModel viewModel) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.s,
      ),
      child: AdminMetricCard(
        icon: Icons.payments_outlined,
        iconBackgroundColor: AppColors.primary,
        iconColor: AppColors.surface,
        label: 'Total Revenue',
        value: CurrencyFormatter.format(viewModel.totalRevenue),
      ),
    );
  }

  Widget _buildRecentOrders(
    BuildContext context,
    AdminDashboardViewModel viewModel,
  ) {
    final recentOrders = viewModel.recentOrders;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'Recent Orders',
          onViewAll: () => _navigateTo(context, RouteNames.adminOrders),
        ),
        if (recentOrders.isEmpty)
          _buildEmptyState('No recent orders')
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: recentOrders.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s),
            itemBuilder: (context, index) {
              final order = recentOrders[index];
              return AdminRecentOrderTile(
                order: order,
                onTap: () => Navigator.pushNamed(
                  context,
                  RouteNames.adminOrderDetail,
                  arguments: order.id,
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildLowStockProducts(
    BuildContext context,
    AdminDashboardViewModel viewModel,
  ) {
    final lowStock = viewModel.lowStockProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'Low-Stock Products',
          onViewAll: () => _navigateTo(context, RouteNames.adminInventory),
        ),
        if (lowStock.isEmpty)
          _buildEmptyState('All products are sufficiently stocked.')
        else
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: lowStock.length,
            separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s),
            itemBuilder: (context, index) {
              return AdminLowStockTile(product: lowStock[index]);
            },
          ),
      ],
    );
  }

  Widget _buildRecentlyAddedProducts(
    BuildContext context,
    AdminDashboardViewModel viewModel,
  ) {
    final recentProducts = viewModel.recentlyAddedProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'Recently Added Products',
          onViewAll: () => _navigateTo(context, RouteNames.adminProducts),
        ),
        if (recentProducts.isEmpty)
          _buildEmptyState('No products available.')
        else
          SizedBox(
            height: 195, // Fixed height for horizontal list
            child: ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
              scrollDirection: Axis.horizontal,
              itemCount: recentProducts.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.s),
              itemBuilder: (context, index) {
                return AdminRecentProductCard(product: recentProducts[index]);
              },
            ),
          ),
      ],
    );
  }

  Widget _buildPaymentSummary(
    BuildContext context,
    AdminDashboardViewModel viewModel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminSectionHeader(
          title: 'Payment Summary',
          // Assuming Payment Summary navigates to orders or payments (Figma shows View All)
          // Since no payments route exists in RouteNames, we'll navigate to orders for now.
          onViewAll: () => _navigateTo(context, RouteNames.adminOrders),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
          child: AdminPaymentSummaryCard(
            paidAmount: viewModel.paidAmount,
            failedAmount: viewModel.failedAmount,
            successPercentage: viewModel.paymentSuccessPercentage,
            failurePercentage: viewModel.paymentFailurePercentage,
          ),
        ),
      ],
    );
  }

  Widget _buildEmptyState(String message) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.m,
        vertical: AppSpacing.l,
      ),
      child: Center(
        child: Text(
          message,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ),
    );
  }

  void _navigateTo(BuildContext context, String routeName) {
    Navigator.of(context).pushNamed(routeName);
  }
}
