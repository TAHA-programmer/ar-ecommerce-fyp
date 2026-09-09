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

import '../../../../app/routes/app_router.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/routes/explore_launch_intent.dart';
import '../../../../app/viewmodels/customer_address_state.dart';
import '../../../../app/viewmodels/customer_profile_state.dart';
import '../../../../features/address/models/address_model.dart';
import '../../explore/models/explore_sort_option.dart';

class HomeView extends StatefulWidget {
  const HomeView({super.key});

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> with RouteAware {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<HomeViewModel>().loadHomeData();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute) {
      AppRouter.routeObserver.subscribe(this, route);
    }
  }

  @override
  void dispose() {
    AppRouter.routeObserver.unsubscribe(this);
    super.dispose();
  }

  @override
  void didPopNext() {
    // Returned to Home from a pushed screen (e.g. Product Details) — refresh
    // the view-history / stats rails so a just-viewed product shows up in
    // "Recently Viewed" without a manual pull-to-refresh.
    if (mounted) {
      context.read<HomeViewModel>().reloadDynamicSections();
    }
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

  void _openExplore(ExploreLaunchIntent intent) {
    Navigator.pushNamed(context, RouteNames.explore, arguments: intent);
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
                    else if (viewModel.showFullScreenError)
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
                      SliverToBoxAdapter(child: _buildPopular(viewModel)),
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

    // The delivery-address row is driven by the authoritative default-address
    // pointer. It renders ONLY once the address state has settled AND a valid
    // default exists — otherwise the whole row (icon included) is absent. Its
    // loading/failure is structurally isolated from the product sections
    // (separate slivers, no shared future).
    final addressState = context.watch<CustomerAddressState>();
    final AddressModel? defaultAddress = addressState.isLoading
        ? null
        : addressState.defaultAddress;

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
          if (defaultAddress != null) ...[
            const SizedBox(height: 4),
            _DeliveryAddressRow(address: defaultAddress),
          ],
        ],
      ),
    );
  }

  // ── sections ─────────────────────────────────────────────────────────────

  Widget _buildShopByCategory(HomeViewModel viewModel) {
    final hasCategories = viewModel.categories.isNotEmpty;

    // Categories failed and there is no last-good list to fall back on →
    // a compact inline retry strip. The product sections below are untouched.
    if (viewModel.categoriesStatus == HomeSectionStatus.error &&
        !hasCategories) {
      return _SectionRetryStrip(
        label: "Couldn't load categories.",
        onRetry: viewModel.retryCategories,
      );
    }
    // Still loading, or genuinely empty → hide the whole section.
    if (!hasCategories) return const SizedBox.shrink();

    // `ready`, or `error` with a last-good list → render it.
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Shop by Category',
          onSeeAll: () =>
              _openExplore(const ExploreLaunchIntent(fromHome: true)),
        ),
        SizedBox(
          height: 100,
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
    if (viewModel.bestSellersStatus != HomeSectionStatus.ready) {
      return const SizedBox.shrink();
    }
    final products = viewModel.bestSellers;
    // Genuine `unitsSold` data → "Best Sellers". Otherwise the honest
    // rating fallback → "Top Rated" (never a fabricated sales claim).
    final title = viewModel.bestSellersUsesRealSalesData
        ? 'Best Sellers'
        : 'Top Rated';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: title,
          onSeeAll: () => _openExplore(
            ExploreLaunchIntent(
              fromHome: true,
              productIds: viewModel.bestSellersSeeAllIds,
            ),
          ),
        ),
        SizedBox(
          height: 320,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: VerticalProductCard(
                  product: product,
                  width: 200,
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

  Widget _buildFeaturedProducts(HomeViewModel viewModel) {
    if (viewModel.featuredStatus != HomeSectionStatus.ready) {
      return const SizedBox.shrink();
    }
    final products = viewModel.featuredProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Featured Products',
          onSeeAll: () => _openExplore(
            ExploreLaunchIntent(
              fromHome: true,
              productIds: viewModel.featuredSeeAllIds,
            ),
          ),
        ),
        SizedBox(
          height: 400,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Container(
                width: 280,
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
    if (viewModel.newArrivalsStatus != HomeSectionStatus.ready) {
      return const SizedBox.shrink();
    }
    final products = viewModel.newArrivals;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'New Arrivals',
          onSeeAll: () => _openExplore(
            const ExploreLaunchIntent(
              fromHome: true,
              sortOption: ExploreSortOption.newest,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final product = products[index];
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
    if (viewModel.arEnabledStatus != HomeSectionStatus.ready) {
      return const SizedBox.shrink();
    }
    final products = viewModel.arEnabledProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'AR Enabled Products',
          onSeeAll: () => _openExplore(
            const ExploreLaunchIntent(fromHome: true, arOnly: true),
          ),
        ),
        SizedBox(
          height: 340,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: VerticalProductCard(
                  product: product,
                  width: 220,
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

  Widget _buildVirtualTryOn(HomeViewModel viewModel) {
    if (viewModel.virtualTryOnStatus != HomeSectionStatus.ready) {
      return const SizedBox.shrink();
    }
    final products = viewModel.virtualTryOnCollection;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Virtual Try-On Collection',
          onSeeAll: () => _openExplore(
            const ExploreLaunchIntent(fromHome: true, tryOnOnly: true),
          ),
        ),
        SizedBox(
          height: 340,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: VerticalProductCard(
                  product: product,
                  width: 220,
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

  Widget _buildPopular(HomeViewModel viewModel) {
    if (viewModel.popularFurnitureDecorStatus != HomeSectionStatus.ready) {
      return const SizedBox.shrink();
    }
    final products = viewModel.popularFurnitureDecor;
    // Genuine `favoriteCount` data → "Popular Furniture & Decor". Otherwise
    // the honest rating fallback → "Top Rated Furniture & Decor".
    final title = viewModel.popularUsesRealFavoriteData
        ? 'Popular Furniture & Decor'
        : 'Top Rated Furniture & Decor';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: title,
          onSeeAll: () => _openExplore(
            ExploreLaunchIntent(
              fromHome: true,
              productIds: viewModel.popularSeeAllIds,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: products.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final product = products[index];
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
    if (viewModel.recentlyViewedStatus != HomeSectionStatus.ready) {
      return const SizedBox.shrink();
    }
    final products = viewModel.recentlyViewedProducts;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        HomeSectionHeader(
          title: 'Recently Viewed',
          // "See all" (→ the dedicated page) only when the customer has more
          // than the three shown — otherwise there is nothing extra to see.
          onSeeAll: viewModel.recentlyViewedHasSeeAll
              ? () => Navigator.pushNamed(context, RouteNames.recentlyViewed)
              : null,
        ),
        SizedBox(
          height: 320,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: products.length,
            itemBuilder: (context, index) {
              final product = products[index];
              return Padding(
                padding: const EdgeInsets.only(right: 12.0),
                child: VerticalProductCard(
                  product: product,
                  width: 200,
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
}

/// Tappable delivery-address row (replaces the old hardcoded
/// "Deliver to, Adiala Road, Rawalpindi" + its down-arrow). Shown only when a
/// valid default address exists. Tapping opens Saved Addresses.
class _DeliveryAddressRow extends StatelessWidget {
  final AddressModel address;

  const _DeliveryAddressRow({required this.address});

  @override
  Widget build(BuildContext context) {
    final parts = [
      address.addressLine1.trim(),
      address.city.trim(),
    ].where((s) => s.isNotEmpty).toList();
    final summary = parts.isNotEmpty
        ? parts.join(', ')
        : (address.label?.trim().isNotEmpty ?? false
              ? address.label!.trim()
              : 'Saved address');

    return InkWell(
      onTap: () => Navigator.pushNamed(context, RouteNames.savedAddresses),
      borderRadius: BorderRadius.circular(6),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(
              Icons.location_on,
              size: 14,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: 4),
            const Text(
              'Deliver to ',
              style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
            ),
            Flexible(
              child: Text(
                summary,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Compact inline "this one section failed — Retry" strip. Never blanks the
/// rest of Home.
class _SectionRetryStrip extends StatelessWidget {
  final String label;
  final VoidCallback onRetry;

  const _SectionRetryStrip({required this.label, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textSecondary,
              ),
            ),
          ),
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        ],
      ),
    );
  }
}
