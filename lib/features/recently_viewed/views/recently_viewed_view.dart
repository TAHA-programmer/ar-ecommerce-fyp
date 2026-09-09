import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes/route_names.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/data/commerce_database.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../../../core/widgets/states/app_empty_state.dart';
import '../../../core/widgets/states/app_error_state.dart';
import '../../../core/widgets/states/app_loading_indicator.dart';
import '../../home/widgets/cards/wide_product_card.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../../product_details/repositories/recently_viewed_repository.dart';
import '../viewmodels/recently_viewed_viewmodel.dart';

/// The dedicated Recently Viewed page (Dynamic Home Content Stage 3). Reached
/// from Home's "Recently Viewed" section "See all" — shown only when the
/// customer has more than 3 eligible items in their history. Preserves
/// newest-first order; reuses the same [WideProductCard] Home's New Arrivals
/// rail uses.
class RecentlyViewedView extends StatelessWidget {
  const RecentlyViewedView({super.key});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => RecentlyViewedViewModel(
        repository: context.read<RecentlyViewedRepository>(),
        db: context.read<CommerceDatabase>(),
        shoppingState: context.read<CustomerShoppingState>(),
        productDetailsRepository: context.read<ProductDetailsRepository>(),
      ),
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Column(
            children: [
              _buildHeader(context),
              Expanded(
                child: Consumer<RecentlyViewedViewModel>(
                  builder: (context, viewModel, child) {
                    if (viewModel.isLoading && viewModel.products.isEmpty) {
                      return const Center(child: AppLoadingIndicator());
                    }
                    if (viewModel.hasError) {
                      return AppErrorState(
                        message:
                            "We couldn't load your recently viewed products.",
                        onRetry: viewModel.refresh,
                      );
                    }
                    if (viewModel.isEmpty) {
                      return AppEmptyState(
                        title: 'Nothing here yet',
                        message:
                            'Products you open will show up here so you can '
                            'find them again.',
                        actionLabel: 'Explore Products',
                        icon: Icons.history,
                        onAction: () {
                          Navigator.popUntil(context, (route) => route.isFirst);
                          Navigator.pushReplacementNamed(
                            context,
                            RouteNames.explore,
                          );
                        },
                      );
                    }
                    return RefreshIndicator(
                      color: AppColors.primary,
                      onRefresh: viewModel.refresh,
                      child: ListView.separated(
                        physics: const AlwaysScrollableScrollPhysics(),
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
                        itemCount: viewModel.products.length,
                        separatorBuilder: (_, _) => const SizedBox(height: 12),
                        itemBuilder: (context, index) {
                          final product = viewModel.products[index];
                          return WideProductCard(
                            product: product,
                            isFavorite: viewModel.isFavorite(product.id),
                            onFavoriteToggle: () => viewModel
                                .toggleFavorite(product.id)
                                .then((error) {
                                  if (error != null && context.mounted) {
                                    AppToast.error(context, error);
                                  }
                                }),
                            onAddToCart: () =>
                                viewModel.addToCart(product.id).then((error) {
                                  if (error != null && context.mounted) {
                                    AppToast.error(context, error);
                                  }
                                }),
                          );
                        },
                      ),
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
          Expanded(
            child: Text(
              'Recently Viewed',
              style: AppTypography.headingMedium,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }
}
