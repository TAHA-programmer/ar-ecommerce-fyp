import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/navigation/customer_bottom_navigation.dart';
import '../../../../core/widgets/navigation/customer_header.dart';
import '../../../../core/widgets/states/app_empty_state.dart';
import '../../../../core/widgets/states/app_loading_indicator.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../viewmodels/explore_viewmodel.dart';
import '../widgets/applied_filter_chips.dart';
import '../widgets/explore_product_card.dart';
import '../widgets/explore_search_bar.dart';
import '../widgets/filter_bottom_sheet.dart';
import '../widgets/quick_category_chips.dart';
import '../widgets/sort_bottom_sheet.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/routes/explore_launch_intent.dart';

class ExploreView extends StatefulWidget {
  final ExploreLaunchIntent? intent;

  const ExploreView({super.key, this.intent});

  @override
  State<ExploreView> createState() => _ExploreViewState();
}

class _ExploreViewState extends State<ExploreView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        final viewModel = context.read<ExploreViewModel>();

        if (widget.intent != null) {
          viewModel.applyIntent(widget.intent!);
        }

        viewModel.loadCatalog();

        if (widget.intent?.openFilterSheet == true) {
          _showFilterSheet(context);
        }
      }
    });
  }

  void _showFilterSheet(BuildContext context) {
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    final viewModel = context.read<ExploreViewModel>();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: DraggableScrollableSheet(
          initialChildSize: 0.9,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (_, scrollController) => FilterBottomSheet(
            initialFilterState: viewModel.activeFilterState,
            onApply: (newState) {
              viewModel.applyFilters(newState);
            },
          ),
        ),
      ),
    );
  }

  void _showSortSheet(BuildContext context) {
    FocusScope.of(context).unfocus(); // Dismiss keyboard
    final viewModel = context.read<ExploreViewModel>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => SortBottomSheet(
        initialSortOption: viewModel.activeSortOption,
        onApply: (newSort) {
          viewModel.applySort(newSort);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<ExploreViewModel>(
        builder: (context, viewModel, child) {
          return Stack(
            children: [
              RefreshIndicator(
                color: AppColors.primary,
                backgroundColor: Colors.white,
                onRefresh: () => viewModel.refresh(),
                child: CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverToBoxAdapter(
                      child: CustomerHeader(cartCount: viewModel.cartCount),
                    ),
                    SliverToBoxAdapter(child: const SizedBox(height: 16)),
                    SliverToBoxAdapter(
                      child: ExploreSearchBar(
                        searchText: viewModel.searchText,
                        onChanged: viewModel.updateSearchText,
                        onFilterTap: () => _showFilterSheet(context),
                      ),
                    ),
                    SliverToBoxAdapter(child: const SizedBox(height: 16)),
                    SliverToBoxAdapter(
                      child: QuickCategoryChips(
                        activeCategory: viewModel.activeCategory,
                        onCategorySelected: viewModel.setCategory,
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          left: 16,
                          right: 16,
                          top: 16,
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              viewModel.filteredProducts.length == 1
                                  ? '1 Product'
                                  : '${viewModel.filteredProducts.length} Products',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: AppColors.textPrimary,
                              ),
                            ),
                            Row(
                              children: [
                                GestureDetector(
                                  onTap: () => _showFilterSheet(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppColors.neutralLight,
                                        width: 1,
                                      ),
                                    ),
                                    child: const Text(
                                      'Filter',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                GestureDetector(
                                  onTap: () => _showSortSheet(context),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 12,
                                      vertical: 6,
                                    ),
                                    decoration: BoxDecoration(
                                      color: Colors.white,
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: AppColors.neutralLight,
                                        width: 1,
                                      ),
                                    ),
                                    child: const Text(
                                      'Sort',
                                      style: TextStyle(
                                        fontFamily: 'Inter',
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: AppColors.textPrimary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: AppliedFilterChips(
                        filterState: viewModel.activeFilterState,
                        onClearAll: viewModel.clearAllFilters,
                        onFilterRemoved: viewModel.applyFilters,
                      ),
                    ),
                    SliverToBoxAdapter(child: const SizedBox(height: 16)),
                    if (viewModel.isLoading)
                      const SliverFillRemaining(
                        child: Center(child: AppLoadingIndicator()),
                      )
                    else if (viewModel.filteredProducts.isEmpty)
                      SliverFillRemaining(
                        child: AppEmptyState(
                          title: 'No products found',
                          message:
                              'Try adjusting your filters or search query.',
                          actionLabel: 'Clear Filters',
                          onAction: viewModel.clearAllFilters,
                        ),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.only(
                          left: 16,
                          right: 16,
                          bottom: MediaQuery.of(context).padding.bottom + 100,
                        ),
                        sliver: SliverGrid(
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                                crossAxisCount: 2,
                                mainAxisSpacing: 16,
                                crossAxisSpacing: 16,
                                childAspectRatio: 0.72, // Compact card geometry
                              ),
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final product = viewModel.filteredProducts[index];
                            return ExploreProductCard(
                              product: product,
                              isFavorite: viewModel.isFavorite(
                                product.summary.id,
                              ),
                              onFavoriteTap: () {
                                viewModel
                                    .toggleFavorite(product.summary.id)
                                    .then((error) {
                                      if (error != null && context.mounted) {
                                        AppToast.error(context, error);
                                      }
                                    });
                              },
                              onAddToCartTap: () {
                                viewModel.addToCart(product.summary.id).then((
                                  error,
                                ) {
                                  if (error != null && context.mounted) {
                                    AppToast.error(context, error);
                                  }
                                });
                              },
                              onTap: () {
                                Navigator.pushNamed(
                                  context,
                                  RouteNames.productDetails,
                                  arguments: product.summary.id,
                                );
                              },
                            );
                          }, childCount: viewModel.filteredProducts.length),
                        ),
                      ),
                  ],
                ),
              ),
              const Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: CustomerBottomNavigation(selectedIndex: 1),
              ),
            ],
          );
        },
      ),
    );
  }
}
