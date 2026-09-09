import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/widgets/navigation/customer_bottom_navigation.dart';
import '../../../../core/widgets/navigation/customer_header.dart';
import '../../../../core/widgets/states/app_error_state.dart';
import '../viewmodels/home_viewmodel.dart';
import '../widgets/cards/featured_product_card.dart';
import '../widgets/cards/horizontal_split_product_card.dart';
import '../widgets/cards/vertical_product_card.dart';
import '../widgets/cards/wide_product_card.dart';
import '../widgets/category_tile.dart';
import '../widgets/home_hero_carousel.dart';
import '../widgets/home_search_bar.dart';
import '../widgets/home_section_header.dart';

import '../../../../app/routes/route_names.dart';
import '../../../../app/routes/explore_launch_intent.dart';
import '../../../../app/viewmodels/customer_profile_state.dart';
import '../../explore/models/explore_sort_option.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().loadHomeData();
    });
  }

  void _handleToggleFavorite(HomeViewModel viewModel, String productId) {
    viewModel.toggleFavorite(productId).then((error) {
      if (error != null && mounted) AppToast.error(context, error);
    });
  }

  void _handleAddToCart(HomeViewModel viewModel, String productId) {
    viewModel.addToCart(productId).then((error) {
      if (error != null && mounted) AppToast.error(context, error);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Consumer<HomeViewModel>(
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
                    if (viewModel.isLoading)
                      const SliverFillRemaining(
                        child: Center(
                          child: CircularProgressIndicator(
                            color: AppColors.primary,
                          ),
                        ),
                      )
                    else if (viewModel.hasError && viewModel.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: AppErrorState(
                          message:
                              "We couldn't load your home feed. Please check "
                              'your connection and try again.',
                          onRetry: viewModel.retry,
                        ),
                      )
                    else ...[
                      SliverToBoxAdapter(child: _buildGreeting()),
                      const SliverToBoxAdapter(child: HomeSearchBar()),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      SliverToBoxAdapter(
                        child: HomeHeroCarousel(banners: viewModel.banners),
                      ),
                      const SliverToBoxAdapter(child: SizedBox(height: 24)),
                      SliverToBoxAdapter(
                        child: _buildShopByCategory(viewModel),
                      ),
                      SliverToBoxAdapter(child: _buildBestSellers(viewModel)),
                      SliverToBoxAdapter(
                        child: _buildFeaturedProducts(viewModel),
                      ),
                      SliverToBoxAdapter(child: _buildNewArrivals(viewModel)),
                      SliverToBoxAdapter(child: _buildArEnabled(viewModel)),
                      SliverToBoxAdapter(child: _buildVirtualTryOn(viewModel)),
                      SliverToBoxAdapter(
                        child: _buildPopularFurniture(viewModel),
                      ),
                      SliverToBoxAdapter(
                        child: _buildRecentlyViewed(viewModel),
                      ),
                    ],
                    // Bottom padding for the floating nav bar
                    SliverToBoxAdapter(
                      child: SizedBox(
                        height: MediaQuery.of(context).padding.bottom + 100,
                      ),
                    ),
                  ],
                ),
              ),
              // Floating Bottom Navigation
              const Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: CustomerBottomNavigation(selectedIndex: 0),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildGreeting() {
    final fullName = context.watch<CustomerProfileState>().fullName.trim();
    final firstName = fullName.isEmpty
        ? 'there'
        : fullName.split(RegExp(r'\s+')).first;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RichText(
            text: TextSpan(
              style: const TextStyle(
                fontFamily: 'Inter',
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: AppColors.textPrimary,
              ),
              children: [
                const TextSpan(text: 'Hello, '),
                TextSpan(
                  text: '$firstName ',
                  style: const TextStyle(color: AppColors.primary),
                ),
                const TextSpan(text: '👋', style: TextStyle(fontSize: 16)),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const Icon(
                Icons.location_on,
                size: 14,
                color: AppColors.textSecondary,
              ),
              const SizedBox(width: 4),
              const Text(
                'Deliver to, ',
                style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
              ),
              Expanded(
                child: Text(
                  'Adiala Road, Rawalpindi',
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
              const SizedBox(width: 2),
              const Icon(
                Icons.keyboard_arrow_down,
                size: 16,
                color: AppColors.primary,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildShopByCategory(HomeViewModel viewModel) {
    if (viewModel.categories.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Shop by Category',
          onSeeAll: () {
            Navigator.pushNamed(context, RouteNames.explore);
          },
        ),
        SizedBox(
          height: 100, // Increased height for larger category tiles
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            itemCount: viewModel.categories.length,
            itemBuilder: (context, index) {
              return CategoryTile(category: viewModel.categories[index]);
            },
          ),
        ),
        const SizedBox(height: 12),
      ],
    );
  }

  Widget _buildBestSellers(HomeViewModel viewModel) {
    if (viewModel.bestSellers.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Best Sellers',
          onSeeAll: () {
            Navigator.pushNamed(
              context,
              RouteNames.explore,
              arguments: const ExploreLaunchIntent(
                sortOption: ExploreSortOption.mostPopular,
              ),
            );
          },
        ),
        SizedBox(
          height: 320, // Increased for wider card proportion
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: viewModel.bestSellers.length,
            itemBuilder: (context, index) {
              final product = viewModel.bestSellers[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: VerticalProductCard(
                  product: product,
                  width: 200, // Increased width
                  aspectRatio: 1.0, // Match Figma square image proportion
                  isFavorite: viewModel.isFavorite(product.id),
                  onFavoriteToggle: () =>
                      _handleToggleFavorite(viewModel, product.id),
                  // Removed onAddToCart as per Figma Best Sellers
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildFeaturedProducts(HomeViewModel viewModel) {
    if (viewModel.featuredProducts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Featured Products',
          onSeeAll: () {
            Navigator.pushNamed(
              context,
              RouteNames.explore,
              arguments: ExploreLaunchIntent(
                productIds: viewModel.featuredProducts
                    .map((p) => p.id)
                    .toList(),
              ),
            );
          },
        ),
        SizedBox(
          height: 400, // Allow full height for card
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: viewModel.featuredProducts.length,
            itemBuilder: (context, index) {
              final product = viewModel.featuredProducts[index];
              return Container(
                width: 280, // Fixed width for featured products
                margin: const EdgeInsets.only(right: 12),
                child: FeaturedProductCard(
                  product: product,
                  isFavorite: viewModel.isFavorite(product.id),
                  onFavoriteToggle: () =>
                      _handleToggleFavorite(viewModel, product.id),
                  onAddToCart: () => _handleAddToCart(viewModel, product.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildNewArrivals(HomeViewModel viewModel) {
    if (viewModel.newArrivals.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'New Arrivals',
          onSeeAll: () {
            Navigator.pushNamed(
              context,
              RouteNames.explore,
              arguments: const ExploreLaunchIntent(
                sortOption: ExploreSortOption.newest,
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: viewModel.newArrivals.take(4).length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final product = viewModel.newArrivals[index];
              return WideProductCard(
                product: product,
                isFavorite: viewModel.isFavorite(product.id),
                onFavoriteToggle: () =>
                    _handleToggleFavorite(viewModel, product.id),
                onAddToCart: () => _handleAddToCart(viewModel, product.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildArEnabled(HomeViewModel viewModel) {
    if (viewModel.arEnabledProducts.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'AR Enabled Products',
          onSeeAll: () {
            Navigator.pushNamed(
              context,
              RouteNames.explore,
              arguments: const ExploreLaunchIntent(arOnly: true),
            );
          },
        ),
        SizedBox(
          height: 340, // Increased for wider card proportion
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: viewModel.arEnabledProducts.length,
            itemBuilder: (context, index) {
              final product = viewModel.arEnabledProducts[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: VerticalProductCard(
                  product: product,
                  width: 220, // Increased width
                  aspectRatio: 1.0, // Match Figma square image proportion
                  isFavorite: viewModel.isFavorite(product.id),
                  onFavoriteToggle: () =>
                      _handleToggleFavorite(viewModel, product.id),
                  onAddToCart: () => _handleAddToCart(viewModel, product.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildVirtualTryOn(HomeViewModel viewModel) {
    if (viewModel.virtualTryOnCollection.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Virtual Try-On Collection',
          onSeeAll: () {
            Navigator.pushNamed(
              context,
              RouteNames.explore,
              arguments: const ExploreLaunchIntent(tryOnOnly: true),
            );
          },
        ),
        SizedBox(
          height: 340, // Increased height to avoid overflow and fit wider card
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: viewModel.virtualTryOnCollection.length,
            itemBuilder: (context, index) {
              final product = viewModel.virtualTryOnCollection[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: VerticalProductCard(
                  product: product,
                  width: 220, // Widened card
                  aspectRatio: 1.0,
                  isFavorite: viewModel.isFavorite(product.id),
                  onFavoriteToggle: () =>
                      _handleToggleFavorite(viewModel, product.id),
                  onAddToCart: () => _handleAddToCart(viewModel, product.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPopularFurniture(HomeViewModel viewModel) {
    if (viewModel.popularFurniture.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Popular Furniture & Decor',
          onSeeAll: () {
            Navigator.pushNamed(
              context,
              RouteNames.explore,
              arguments: ExploreLaunchIntent(
                productIds: viewModel.popularFurniture
                    .map((p) => p.id)
                    .toList(),
              ),
            );
          },
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: viewModel.popularFurniture.take(4).length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final product = viewModel.popularFurniture[index];
              return HorizontalSplitProductCard(
                product: product,
                isFavorite: viewModel.isFavorite(product.id),
                onFavoriteToggle: () =>
                    _handleToggleFavorite(viewModel, product.id),
                onAddToCart: () => _handleAddToCart(viewModel, product.id),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentlyViewed(HomeViewModel viewModel) {
    if (viewModel.recentlyViewed.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Recently Viewed',
          onSeeAll: () {
            Navigator.pushNamed(
              context,
              RouteNames.explore,
              arguments: ExploreLaunchIntent(
                productIds: viewModel.recentlyViewed.map((p) => p.id).toList(),
              ),
            );
          },
        ),
        SizedBox(
          height: 280, // Increased height to avoid overflow
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: viewModel.recentlyViewed.length,
            itemBuilder: (context, index) {
              final product = viewModel.recentlyViewed[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: VerticalProductCard(
                  product: product,
                  width: 180, // Wider width
                  aspectRatio: 1.0,
                  isFavorite: viewModel.isFavorite(product.id),
                  onFavoriteToggle: () =>
                      _handleToggleFavorite(viewModel, product.id),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}
