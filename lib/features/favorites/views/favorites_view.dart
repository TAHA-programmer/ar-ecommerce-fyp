import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/routes/route_names.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/states/app_empty_state.dart';
import '../../../core/widgets/states/app_loading_indicator.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../../explore/widgets/explore_product_card.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../viewmodels/favorites_viewmodel.dart';

class FavoritesView extends StatelessWidget {
  const FavoritesView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => FavoritesViewModel(
        shoppingState: context.read<CustomerShoppingState>(),
        repository: context.read<ProductDetailsRepository>(),
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Consumer<FavoritesViewModel>(
                  builder: (context, viewModel, child) {
                    if (viewModel.isLoading &&
                        viewModel.favoriteProducts.isEmpty) {
                      return const Center(child: AppLoadingIndicator());
                    }

                    if (viewModel.favoriteProducts.isEmpty) {
                      return AppEmptyState(
                        title: 'No favorites yet',
                        message:
                            'Save products you love and they’ll appear here.',
                        actionLabel: 'Explore Products',
                        onAction: () {
                          Navigator.popUntil(context, (route) => route.isFirst);
                          Navigator.pushReplacementNamed(
                            context,
                            RouteNames.explore,
                          );
                        },
                      );
                    }

                    return CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            bottom: 32,
                            top: 16,
                          ),
                          sliver: SliverGrid(
                            gridDelegate:
                                const SliverGridDelegateWithFixedCrossAxisCount(
                                  crossAxisCount: 2,
                                  mainAxisSpacing: 16,
                                  crossAxisSpacing: 16,
                                  childAspectRatio: 0.72,
                                ),
                            delegate: SliverChildBuilderDelegate((
                              context,
                              index,
                            ) {
                              final product = viewModel.favoriteProducts[index];
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
                            }, childCount: viewModel.favoriteProducts.length),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 16.0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: AppColors.textPrimary.withAlpha(13),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.arrow_back_ios_new,
                size: 16,
                color: AppColors.textPrimary,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Text('Favorites', style: AppTypography.headingMedium),
        ],
      ),
    );
  }
}
