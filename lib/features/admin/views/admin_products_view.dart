import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/category_repository.dart';
import '../../../../core/data/commerce_database.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../app/routes/route_names.dart';
import '../views/admin_shell.dart';
import '../product_management/viewmodels/admin_product_management_viewmodel.dart';
import '../product_management/models/admin_product_management_mode.dart';
import '../product_management/models/admin_product_sort_option.dart';
import '../product_management/models/admin_category_config.dart';
import '../product_management/models/admin_category_sort_option.dart';
import '../product_management/models/admin_product_filter_state.dart';
import '../product_management/widgets/admin_product_card.dart';
import '../product_management/widgets/admin_product_filter_sheet.dart';
import '../product_management/widgets/admin_product_sort_sheet.dart';
import '../product_management/widgets/admin_category_card.dart';
import '../product_management/widgets/admin_category_filter_sheet.dart';
import '../product_management/widgets/admin_category_sort_sheet.dart';

class AdminProductsView extends StatelessWidget {
  const AdminProductsView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AdminProductManagementViewModel(
        context.read<CommerceDatabase>(),
        context.read<CategoryRepository>(),
        storageService: context.read<StorageService>(),
      ),
      child: const _AdminProductsViewContent(),
    );
  }
}

class _AdminProductsViewContent extends StatefulWidget {
  const _AdminProductsViewContent();

  @override
  State<_AdminProductsViewContent> createState() =>
      _AdminProductsViewContentState();
}

class _AdminProductsViewContentState extends State<_AdminProductsViewContent> {
  final TextEditingController _searchController = TextEditingController();
  final TextEditingController _categorySearchController =
      TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    _categorySearchController.dispose();
    super.dispose();
  }

  // --- Products Dialogs ---

  void _showDeleteDialog(
    BuildContext context,
    String productId,
    String productName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text(
          'Are you sure you want to delete\n"$productName"?\n\nThis will remove the product from the current mock catalog.',
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              final deleted = await context
                  .read<AdminProductManagementViewModel>()
                  .deleteProduct(ctx, productId);
              if (deleted && ctx.mounted) Navigator.of(ctx).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: Colors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(
    BuildContext context,
    String productId,
    String productName,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Edit Product?'),
        content: Text('You are about to edit\n"$productName".'),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.textPrimary,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              Navigator.of(
                context,
              ).pushNamed(RouteNames.adminEditProduct, arguments: productId);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  void _showFilterSheet(BuildContext context) {
    final viewModel = context.read<AdminProductManagementViewModel>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => FractionallySizedBox(
        heightFactor: 0.85,
        child: AdminProductFilterSheet(
          initialFilterState: viewModel.filterState,
          onApply: (newState) {
            viewModel.updateFilter(newState);
          },
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    final viewModel = context.read<AdminProductManagementViewModel>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AdminProductSortSheet(
        initialSortOption: viewModel.sortOption,
        onApply: (newSort) {
          viewModel.setSortOption(newSort);
        },
      ),
    );
  }

  // --- Categories Dialogs ---

  void _showCategoryFilterSheet(BuildContext context) {
    final viewModel = context.read<AdminProductManagementViewModel>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AdminCategoryFilterSheet(
        initialStatus: viewModel.categoryFilterStatus,
        onApply: (newStatus) {
          viewModel.setCategoryFilterStatus(newStatus);
        },
      ),
    );
  }

  void _showCategorySortSheet(BuildContext context) {
    final viewModel = context.read<AdminProductManagementViewModel>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AdminCategorySortSheet(
        initialSortOption: viewModel.categorySortOption,
        onApply: (newSort) {
          viewModel.setCategorySortOption(newSort);
        },
      ),
    );
  }

  void _openAddCategory(BuildContext context) {
    Navigator.of(context).pushNamed(RouteNames.adminAddCategory);
  }

  void _openEditCategory(BuildContext context, AdminCategoryViewItem item) {
    Navigator.of(
      context,
    ).pushNamed(RouteNames.adminEditCategory, arguments: item.categoryId);
  }

  void _showDeleteCategoryDialog(
    BuildContext context,
    AdminCategoryViewItem item,
  ) {
    final viewModel = context.read<AdminProductManagementViewModel>();
    // Eligibility is decided entirely by the ViewModel (canDeleteCategory /
    // categoryDeletionBlockedReason) - this View only picks which dialog to
    // show based on that answer, it never re-derives the rule itself.
    final blockedReason = viewModel.categoryDeletionBlockedReason(item);

    if (blockedReason != null) {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Cannot Delete Category'),
          content: Text(blockedReason),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Understood'),
            ),
          ],
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Delete Category?'),
          content: Text(
            'Are you sure you want to delete\n"${item.displayName}"?\n\nThis cannot be undone.',
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: Text(
                'Cancel',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(ctx).pop();
                await viewModel.deleteCategory(context, item);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.error,
                foregroundColor: Colors.white,
              ),
              child: const Text('Delete'),
            ),
          ],
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminProductManagementViewModel>();
    final isProductsMode =
        viewModel.mode == AdminProductManagementMode.products;

    return AdminShell(
      currentIndex: 1,
      title: 'Products',
      showGreeting: false,
      child: Column(
        children: [
          // Mode Selector and Add Product Button
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: _buildModeButton(
                        'Products',
                        isProductsMode,
                        () => viewModel.setMode(
                          AdminProductManagementMode.products,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _buildModeButton(
                        'Categories',
                        !isProductsMode,
                        () => viewModel.setMode(
                          AdminProductManagementMode.categories,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () {
                    if (isProductsMode) {
                      Navigator.of(
                        context,
                      ).pushNamed(RouteNames.adminAddProduct);
                    } else {
                      _openAddCategory(context);
                    }
                  },
                  icon: const Icon(Icons.add, color: AppColors.primary),
                  label: Text(isProductsMode ? 'Add Product' : 'Add Category'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.primary,
                    side: const BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
                if (isProductsMode) ...[
                  const SizedBox(height: 8),
                  OutlinedButton.icon(
                    onPressed: () => Navigator.of(
                      context,
                    ).pushNamed(RouteNames.adminArMedia),
                    icon: const Icon(
                      Icons.view_in_ar_outlined,
                      color: AppColors.primary,
                    ),
                    label: const Text('AR & Media Management'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primaryDark,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ],
              ],
            ),
          ),

          if (isProductsMode) ...[
            _buildProductsMode(context, viewModel),
          ] else ...[
            _buildCategoriesMode(context, viewModel),
          ],
        ],
      ),
    );
  }

  Widget _buildProductsMode(
    BuildContext context,
    AdminProductManagementViewModel viewModel,
  ) {
    final products = viewModel.filteredProducts;
    return Expanded(
      child: Column(
        children: [
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _searchController,
              onChanged: viewModel.setSearchQuery,
              style: AppTypography.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search products by name, category, or SKU...',
                hintMaxLines: 1,
                hintStyle: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  overflow: TextOverflow.ellipsis,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textSecondary,
                ),
                suffixIcon: GestureDetector(
                  onTap: () => _showFilterSheet(context),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: AppColors.primary,
                        width: viewModel.filterState.hasActiveFilters ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.tune, color: AppColors.primary),
                  ),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),

          // Quick Info & Sort
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${products.length} Products',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _showSortSheet(context),
                  child: Row(
                    children: [
                      Text(
                        'Sort: ',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        viewModel.sortOption.label,
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Product List
          Expanded(
            child: products.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No products found',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (viewModel.filterState.hasActiveFilters) ...[
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: viewModel.resetFilters,
                            child: const Text('Reset Filters'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: products.length,
                    itemBuilder: (context, index) {
                      final product = products[index];
                      return AdminProductCard(
                        product: product,
                        onEdit: () =>
                            _showEditDialog(context, product.id, product.title),
                        onDelete: () => _showDeleteDialog(
                          context,
                          product.id,
                          product.title,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCategoriesMode(
    BuildContext context,
    AdminProductManagementViewModel viewModel,
  ) {
    final categories = viewModel.filteredCategories;
    final hasActiveFilters =
        viewModel.categoryFilterStatus != AdminProductStatusFilter.all;

    return Expanded(
      child: Column(
        children: [
          // Search and Filter Bar
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0),
            child: TextField(
              controller: _categorySearchController,
              onChanged: viewModel.setCategorySearchQuery,
              style: AppTypography.bodySmall,
              decoration: InputDecoration(
                hintText: 'Search categories by name...',
                hintMaxLines: 1,
                hintStyle: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                  overflow: TextOverflow.ellipsis,
                ),
                prefixIcon: const Icon(
                  Icons.search,
                  color: AppColors.textSecondary,
                ),
                suffixIcon: GestureDetector(
                  onTap: () => _showCategoryFilterSheet(context),
                  child: Container(
                    margin: const EdgeInsets.fromLTRB(4, 4, 8, 4),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(
                        color: AppColors.primary,
                        width: hasActiveFilters ? 2 : 1,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.tune, color: AppColors.primary),
                  ),
                ),
                filled: true,
                fillColor: Colors.white,
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 0,
                  horizontal: 16,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: AppColors.primary),
                ),
              ),
            ),
          ),

          // Quick Info & Sort
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    '${categories.length} Categories',
                    style: AppTypography.bodyMedium.copyWith(
                      fontWeight: FontWeight.w600,
                      color: AppColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                GestureDetector(
                  onTap: () => _showCategorySortSheet(context),
                  child: Row(
                    children: [
                      Text(
                        'Sort: ',
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                      Text(
                        viewModel.categorySortOption.label,
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.w600,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      const Icon(Icons.arrow_drop_down, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Category List
          Expanded(
            child: viewModel.isCategoriesLoading
                ? const Center(child: CircularProgressIndicator())
                : viewModel.hasCategoriesError
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'Could not load categories',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Check your connection and try again.',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  )
                : categories.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No categories found',
                          style: AppTypography.bodyLarge.copyWith(
                            color: AppColors.textSecondary,
                          ),
                        ),
                        if (hasActiveFilters) ...[
                          const SizedBox(height: 16),
                          TextButton(
                            onPressed: viewModel.resetCategoryFilters,
                            child: const Text('Reset Filters'),
                          ),
                        ],
                      ],
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    itemCount: categories.length,
                    itemBuilder: (context, index) {
                      final item = categories[index];
                      return AdminCategoryCard(
                        item: item,
                        onEdit: () => _openEditCategory(context, item),
                        onDelete: () =>
                            _showDeleteCategoryDialog(context, item),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton(String title, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
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
            color: isSelected ? Colors.white : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
