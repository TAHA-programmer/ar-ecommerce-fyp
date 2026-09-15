import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../app/routes/route_names.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/product_image_view.dart';
import '../../../../core/widgets/states/app_empty_state.dart';
import '../../orders_payments/widgets/admin_order_card.dart';
import '../../views/admin_shell.dart';
import '../viewmodels/admin_notifications_viewmodel.dart';

/// Admin's "Notifications" screen - reached from the header's notification
/// bell, matching `AdminReviewsView`'s precedent for a standalone admin
/// surface that isn't one of the four primary bottom-nav tabs.
///
/// Everything shown is real, currently-true data pulled from the same
/// [AdminNotificationsViewModel] the header's numeric badge checks - there is no
/// separate notifications backend, no read/unread state, and no historical
/// log; this is a live "what needs your attention right now" view.
class AdminNotificationsView extends StatelessWidget {
  const AdminNotificationsView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminNotificationsViewModel>();
    final pendingOrders = viewModel.pendingOrders;
    final lowStock = viewModel.lowStockProducts;

    return AdminShell(
      currentIndex: 0,
      title: 'Notifications',
      showGreeting: false,
      child: Column(
        children: [
          _buildTitleRow(context),
          Expanded(
            child: !viewModel.hasNotifications
                ? const AppEmptyState(
                    title: 'All caught up',
                    message: 'No pending orders or low-stock alerts right now.',
                    icon: Icons.notifications_none,
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(
                      AppSpacing.m,
                      0,
                      AppSpacing.m,
                      AppSpacing.m,
                    ),
                    children: [
                      if (pendingOrders.isNotEmpty) ...[
                        _SectionHeader(
                          icon: Icons.schedule,
                          label: 'Pending Orders (${pendingOrders.length})',
                        ),
                        const SizedBox(height: AppSpacing.s),
                        ...pendingOrders.map(
                          (order) => AdminOrderCard(
                            key: ValueKey(
                              'admin_notification_order_${order.id}',
                            ),
                            order: order,
                            onViewDetails: () => Navigator.pushNamed(
                              context,
                              RouteNames.adminOrderDetail,
                              arguments: order.id,
                            ),
                          ),
                        ),
                        const SizedBox(height: AppSpacing.s),
                      ],
                      if (lowStock.isNotEmpty) ...[
                        _SectionHeader(
                          icon: Icons.inventory_2_outlined,
                          label: 'Low Stock Products (${lowStock.length})',
                        ),
                        const SizedBox(height: AppSpacing.s),
                        ...lowStock.map(
                          (product) => _LowStockTile(
                            key: ValueKey(
                              'admin_notification_stock_${product.id}',
                            ),
                            product: product,
                            onTap: () => Navigator.pushNamed(
                              context,
                              RouteNames.adminInventory,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
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
            key: const Key('admin_notifications_back_button'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Text('Notifications', style: AppTypography.title),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String label;

  const _SectionHeader({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: AppColors.primaryDark),
        const SizedBox(width: AppSpacing.xs),
        Text(
          label,
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _LowStockTile extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onTap;

  const _LowStockTile({super.key, required this.product, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: AppRadii.largeBorder,
      child: Container(
        margin: const EdgeInsets.only(bottom: AppSpacing.s),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: AppRadii.largeBorder,
          border: Border.all(color: AppColors.warning.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.all(AppSpacing.s),
        child: Row(
          children: [
            ClipRRect(
              borderRadius: AppRadii.smallBorder,
              child: SizedBox(
                width: 44,
                height: 44,
                child: ProductImageView(
                  imageRef: product.mainImage,
                  fit: BoxFit.cover,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.s),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    product.title,
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'SKU: ${product.sku}',
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.12),
                borderRadius: AppRadii.smallBorder,
              ),
              child: Text(
                '${product.stockQuantity} left',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.warning,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
