import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
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

class ProductDetailsView extends StatelessWidget {
  final String productId;

  const ProductDetailsView({super.key, required this.productId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => ProductDetailsViewModel(
        repository: context.read<ProductDetailsRepository>(),
        shoppingState: context.read<CustomerShoppingState>(),
        categoryRepository: context.read<CategoryRepository>(),
        productId: productId,
        recentlyViewed: context.read<RecentlyViewedRepository>(),
      ),
      child: const _ProductDetailsContent(),
    );
  }
}

class _ProductDetailsContent extends StatelessWidget {
  const _ProductDetailsContent();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ProductDetailsViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: ProductDetailsHeader(
        isFavorite: viewModel.isFavorite,
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
              onTryItOn:
                  () {}, // Not used in HomeProductDetailsLayout, but we need to update it if it's there? Wait, HomeProductDetailsLayout doesn't have onTryItOn. Let's check.
            ),
    );
  }
}
