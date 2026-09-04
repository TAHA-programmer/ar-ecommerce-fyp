import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:twin_ar/core/data/category_repository.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_spacing.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/core/widgets/states/app_empty_state.dart';
import 'package:twin_ar/features/admin/inventory/viewmodels/admin_inventory_viewmodel.dart';
import 'package:twin_ar/features/admin/inventory/widgets/admin_inventory_filter_bar.dart';
import 'package:twin_ar/features/admin/inventory/widgets/admin_inventory_product_card.dart';
import 'package:twin_ar/features/admin/views/admin_shell.dart';

class AdminInventoryView extends StatelessWidget {
  const AdminInventoryView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AdminInventoryViewModel(
        context.read<CommerceDatabase>(),
        context.read<CategoryRepository>(),
      ),
      child: const _AdminInventoryViewContent(),
    );
  }
}

class _AdminInventoryViewContent extends StatefulWidget {
  const _AdminInventoryViewContent();

  @override
  State<_AdminInventoryViewContent> createState() =>
      _AdminInventoryViewContentState();
}

class _AdminInventoryViewContentState
    extends State<_AdminInventoryViewContent> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminInventoryViewModel>();
    final products = viewModel.filteredProducts;

    return AdminShell(
      currentIndex: 2,
      title: 'Inventory',
      showGreeting: false,
      // A single CustomScrollView (header + list/empty-state as slivers)
      // instead of a fixed header + Expanded body: the whole screen scrolls
      // as one unit whenever the viewport is squeezed (e.g. the on-screen
      // keyboard open while searching), so nothing is ever forced to
      // overflow a fixed height.
      child: CustomScrollView(
        key: const Key('admin_inventory_scroll_view'),
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
                  Text('Inventory Management', style: AppTypography.title),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    'Track and manage your product inventory',
                    style: AppTypography.bodySmall,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  AdminInventoryFilterBar(
                    searchController: _searchController,
                    onSearchChanged: viewModel.setSearchQuery,
                    selectedCategory: viewModel.selectedCategory,
                    onCategoryChanged: viewModel.setCategory,
                    lowStockOnly: viewModel.lowStockOnly,
                    onLowStockOnlyChanged: viewModel.setLowStockOnly,
                  ),
                  const SizedBox(height: AppSpacing.m),
                  _buildSummaryRow(products.length),
                ],
              ),
            ),
          ),
          if (products.isEmpty)
            const SliverFillRemaining(
              hasScrollBody: false,
              child: AppEmptyState(
                title: 'No products found',
                message: 'Try a different search term or adjust your filters.',
                icon: Icons.inventory_2_outlined,
              ),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.m,
                0,
                AppSpacing.m,
                AppSpacing.m,
              ),
              sliver: SliverList.builder(
                itemCount: products.length,
                itemBuilder: (context, index) {
                  final product = products[index];
                  return AdminInventoryProductCard(
                    key: ValueKey(product.id),
                    product: product,
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildSummaryRow(int totalProducts) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Total Products: $totalProducts',
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.s,
          runSpacing: AppSpacing.xxs,
          children: [
            _buildLegendDot('In Stock', AppColors.success),
            _buildLegendDot('Low Stock', AppColors.warning),
            _buildLegendDot('Out of Stock', AppColors.error),
          ],
        ),
      ],
    );
  }

  Widget _buildLegendDot(String label, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: AppSpacing.xxs),
        Text(label, style: AppTypography.caption),
      ],
    );
  }
}
