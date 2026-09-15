import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/viewmodels/auth_session_state.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/data/category_repository.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/models/product/product_category.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../../../app/routes/route_names.dart';
import '../../virtual_try_on/models/virtual_try_on_setup_args.dart';
import '../repositories/product_details_repository.dart';
import '../repositories/recently_viewed_repository.dart';
import '../viewmodels/product_details_viewmodel.dart';
import '../widgets/layouts/clothing_product_details_layout.dart';
import '../widgets/layouts/home_product_details_layout.dart';
import '../widgets/product_details_header.dart';
import '../../reviews/repositories/reviews_repository.dart';
import '../../reviews/viewmodels/reviews_viewmodel.dart';

class ProductDetailsView extends StatelessWidget {
  final String productId;

  const ProductDetailsView({super.key, required this.productId});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (context) => ProductDetailsViewModel(
            repository: context.read<ProductDetailsRepository>(),
            shoppingState: context.read<CustomerShoppingState>(),
            categoryRepository: context.read<CategoryRepository>(),
            productId: productId,
            recentlyViewed: context.read<RecentlyViewedRepository>(),
          ),
        ),
        // Ratings/Reviews v1 Stage 6 — independent of ProductDetailsViewModel
        // (its own repository/data source), keyed by the SAME productId.
        // Constructed unconditionally alongside it, not lazily once the
        // product itself finishes loading - the two are separate reads with
        // no ordering dependency.
        ChangeNotifierProvider(
          create: (context) => ReviewsViewModel(
            repository: context.read<ReviewsRepository>(),
            authSessionState: context.read<AuthSessionState>(),
            productId: productId,
          ),
        ),
      ],
      child: const _ProductDetailsContent(),
    );
  }
}

class _ProductDetailsContent extends StatelessWidget {
  const _ProductDetailsContent();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ProductDetailsViewModel>();
    final cartCount = context.watch<CustomerShoppingState>().cartCount;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ProductDetailsHeader(
        isFavorite: viewModel.isFavorite,
        cartCount: cartCount,
        onFavoriteToggle: () {
          viewModel.toggleFavorite().then((error) {
            if (error != null && context.mounted) {
              AppToast.error(context, error);
            }
          });
        },
      ),
      body: viewModel.isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : viewModel.error != null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(viewModel.error!),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () => viewModel.refresh(),
                    child: const Text('Retry'),
                  ),
                ],
              ),
            )
          : viewModel.product == null
          ? const Center(child: Text('Product not found'))
          : viewModel.product!.categoryKind == ProductCategory.clothing
          ? ClothingProductDetailsLayout(
              viewModel: viewModel,
              onViewInRoom: () => Navigator.pushNamed(
                context,
                RouteNames.roomArPreparation,
                arguments: viewModel.product!.summary.id,
              ),
              onTryItOn: () => Navigator.pushNamed(
                context,
                RouteNames.virtualTryOnSetup,
                arguments: VirtualTryOnSetupArgs(
                  productId: viewModel.product!.summary.id,
                  initialColorKey: viewModel.selectedColor?.name,
                  initialSize: viewModel.selectedSize?.name,
                ),
              ),
            )
          : HomeProductDetailsLayout(
              viewModel: viewModel,
              onViewInRoom: () => Navigator.pushNamed(
                context,
                RouteNames.roomArPreparation,
                arguments: viewModel.product!.summary.id,
              ),
              onTryItOn: () {}, // No Try-On affordance on non-clothing layout.
            ),
    );
  }
}
