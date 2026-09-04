import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

import '../../../core/widgets/navigation/customer_bottom_navigation.dart';
import '../../../core/widgets/navigation/customer_header.dart';

import '../viewmodels/cart_viewmodel.dart';
import '../widgets/cart_item_card.dart';
import '../widgets/cart_summary_card.dart';
import '../widgets/empty_cart_state.dart';
import '../../../app/routes/route_names.dart';
import '../../../core/widgets/feedback/app_toast.dart';

class ShoppingCartView extends StatelessWidget {
  const ShoppingCartView({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(context),
            Expanded(
              child: Consumer<CartViewModel>(
                builder: (context, viewModel, child) {
                  if (viewModel.isLoading) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }
                  if (viewModel.error != null) {
                    return Center(
                      child: Text(
                        viewModel.error!,
                        style: AppTypography.bodyMedium,
                      ),
                    );
                  }
                  if (viewModel.populatedItems.isEmpty &&
                      !viewModel.hasUnavailableItems) {
                    return const EmptyCartState();
                  }

                  return CustomScrollView(
                    slivers: [
                      if (viewModel.hasUnavailableItems)
                        SliverToBoxAdapter(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                            child: _UnavailableCartItemsBanner(
                              count: viewModel.unavailableItems.length,
                              onRemoveAll: () {
                                for (final item in viewModel.unavailableItems) {
                                  viewModel.removeFromCart(item.id).then((
                                    error,
                                  ) {
                                    if (error != null && context.mounted) {
                                      AppToast.error(context, error);
                                    }
                                  });
                                }
                              },
                            ),
                          ),
                        ),
                      SliverPadding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        sliver: SliverList(
                          delegate: SliverChildBuilderDelegate((
                            context,
                            index,
                          ) {
                            final item = viewModel.populatedItems[index];
                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: CartItemCard(
                                populatedItem: item,
                                stockWarning: viewModel.stockIssueFor(
                                  item.cartItem.id,
                                ),
                                onQuantityChanged: (newQuantity) {
                                  viewModel
                                      .updateQuantity(
                                        item.cartItem.id,
                                        newQuantity,
                                      )
                                      .then((error) {
                                        if (error != null && context.mounted) {
                                          AppToast.error(context, error);
                                        }
                                      });
                                },
                                onRemove: () {
                                  viewModel
                                      .removeFromCart(item.cartItem.id)
                                      .then((error) {
                                        if (error != null && context.mounted) {
                                          AppToast.error(context, error);
                                        }
                                      });
                                },
                              ),
                            );
                          }, childCount: viewModel.populatedItems.length),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 8,
                          ),
                          child: CartSummaryCard(
                            subtotal: viewModel.subtotal,
                            deliveryFee: viewModel.deliveryFee,
                            discount: viewModel.discount,
                            total: viewModel.total,
                            totalItems: viewModel.populatedItems.fold(
                              0,
                              (sum, item) => sum + item.cartItem.quantity,
                            ),
                          ),
                        ),
                      ),
                      SliverToBoxAdapter(
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              SizedBox(
                                height: 48,
                                child: ElevatedButton(
                                  onPressed: () async {
                                    // Phase 8.11a: re-resolve current product
                                    // data and re-check every line (including
                                    // aggregated variants) BEFORE leaving the
                                    // cart. Blocks navigation with a clear
                                    // toast if anything is unavailable or out
                                    // of stock; the offending lines are also
                                    // marked inline. Nothing is auto-removed.
                                    final error = await viewModel
                                        .validateForCheckout();
                                    if (!context.mounted) return;
                                    if (error != null) {
                                      AppToast.error(context, error);
                                      return;
                                    }
                                    Navigator.pushNamed(
                                      context,
                                      RouteNames.deliveryAddress,
                                    );
                                  },
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: AppColors.primary,
                                    foregroundColor: AppColors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                    elevation: 0,
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        'Proceed to Checkout',
                                        style: AppTypography.bodyLarge.copyWith(
                                          color: AppColors.white,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      const Icon(
                                        Icons.arrow_forward_ios,
                                        size: 16,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                              SizedBox(
                                height: 48,
                                child: OutlinedButton(
                                  onPressed: () {
                                    Navigator.pushNamed(
                                      context,
                                      RouteNames.explore,
                                    );
                                  },
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: AppColors.primary,
                                    side: const BorderSide(
                                      color: AppColors.primary,
                                    ),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(8),
                                    ),
                                  ),
                                  child: Text(
                                    'Continue Shopping',
                                    style: AppTypography.bodyLarge.copyWith(
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 100), // padding for bottom nav
                      ),
                    ],
                  );
                },
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(context),
      extendBody: true,
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Consumer<CartViewModel>(
          builder: (context, viewModel, child) {
            return CustomerHeader(
              cartCount: viewModel.populatedItems.fold(
                0,
                (sum, item) => sum + item.cartItem.quantity,
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          child: Text('My Cart', style: AppTypography.headingMedium),
        ),
      ],
    );
  }

  Widget _buildBottomBar(BuildContext context) {
    return const CustomerBottomNavigation(selectedIndex: 2);
  }
}

/// Minimal, existing-style banner shown when one or more cart lines'
/// products couldn't be resolved (deleted/unpublished/transient lookup
/// failure) - Phase 8.10 requirement: never silently auto-remove such a
/// line, but let the customer clear it themselves.
class _UnavailableCartItemsBanner extends StatelessWidget {
  final int count;
  final VoidCallback onRemoveAll;

  const _UnavailableCartItemsBanner({
    required this.count,
    required this.onRemoveAll,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppColors.warning.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, size: 18, color: AppColors.warning),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              count == 1
                  ? '1 item in your cart is currently unavailable.'
                  : '$count items in your cart are currently unavailable.',
              style: AppTypography.bodySmall,
            ),
          ),
          TextButton(
            onPressed: onRemoveAll,
            child: Text(
              'Remove',
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
