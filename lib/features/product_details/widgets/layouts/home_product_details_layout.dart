import 'package:flutter/material.dart';
import '../../viewmodels/product_details_viewmodel.dart';
import '../furniture_product_gallery.dart';
import '../product_title_block.dart';
import '../product_category_breadcrumb.dart';
import '../expandable_product_description.dart';
import '../product_specifications_card.dart';
import '../product_color_selector.dart';
import '../product_quantity_selector.dart';
import '../product_delivery_card.dart';
import '../product_details_bottom_actions.dart';
import '../../../../core/widgets/feedback/app_toast.dart';

class HomeProductDetailsLayout extends StatelessWidget {
  final ProductDetailsViewModel viewModel;
  final VoidCallback onViewInRoom;
  final VoidCallback onTryItOn;

  const HomeProductDetailsLayout({
    super.key,
    required this.viewModel,
    required this.onViewInRoom,
    required this.onTryItOn,
  });

  @override
  Widget build(BuildContext context) {
    final product = viewModel.product!;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                FurnitureProductGallery(
                  gallery: product.gallery,
                  activeIndex: viewModel.activeGalleryIndex,
                  onThumbnailTap: viewModel.setActiveGalleryIndex,
                  experienceType: product.experienceType,
                ),
                const SizedBox(height: 24),
                ProductTitleBlock(product: product),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ProductCategoryBreadcrumb(
                    categoryName: viewModel.categoryDisplayName,
                    subcategory: product.subcategory,
                  ),
                ),
                const SizedBox(height: 16),
                ExpandableProductDescription(description: product.description),
                const SizedBox(height: 16),
                if (product.specifications.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: ProductSpecificationsCard(
                      specifications: product.specifications,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (product.availableColors.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: ProductColorSelector(
                      availableColors: product.availableColors,
                      selectedColor: viewModel.selectedColor,
                      onColorSelected: viewModel.selectColor,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ProductQuantitySelector(
                    quantity: viewModel.selectedQuantity,
                    canIncrement: viewModel.canIncrementQuantity,
                    onIncrement: () {
                      final message = viewModel.incrementQuantity();
                      if (message != null && context.mounted) {
                        AppToast.warning(context, message);
                      }
                    },
                    onDecrement: viewModel.decrementQuantity,
                  ),
                ),
                const SizedBox(height: 16),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: ProductDeliveryCard(
                    deliveryEstimate: product.deliveryEstimate,
                    warranty: product.warranty,
                  ),
                ),
                const SizedBox(height: 32),
              ],
            ),
          ),
        ),
        ProductDetailsBottomActions(
          experienceType: product.experienceType,
          price: product.summary.currentPrice,
          isOutOfStock: viewModel.isOutOfStock,
          onAddToCart: () {
            viewModel.addToCart().then((error) {
              if (!context.mounted) return;
              if (error != null) {
                AppToast.error(context, error);
              } else {
                AppToast.success(context, 'Added to Cart');
              }
            });
          },
          onViewInRoom: onViewInRoom,
          onTryItOn: onTryItOn,
        ),
        SizedBox(height: safeAreaBottom),
      ],
    );
  }
}
