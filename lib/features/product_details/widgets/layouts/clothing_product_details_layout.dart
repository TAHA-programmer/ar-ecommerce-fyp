import 'package:flutter/material.dart';
import '../../viewmodels/product_details_viewmodel.dart';
import '../clothing_product_gallery.dart';
import '../product_title_block.dart';
import '../expandable_product_description.dart';
import '../product_color_selector.dart';
import '../product_size_selector.dart';
import '../product_quantity_selector.dart';
import '../product_details_bottom_actions.dart';
import '../clothing_benefits_card.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/models/product/product_specification.dart';
import '../../../../core/widgets/feedback/app_toast.dart';

class ClothingProductDetailsLayout extends StatelessWidget {
  final ProductDetailsViewModel viewModel;
  final VoidCallback onViewInRoom;
  final VoidCallback onTryItOn;

  const ClothingProductDetailsLayout({
    super.key,
    required this.viewModel,
    required this.onViewInRoom,
    required this.onTryItOn,
  });

  Widget _buildSpecRow(ProductSpecification spec, IconData icon) {
    return Column(
      children: [
        const Divider(height: 1, color: AppColors.neutralLight),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 20, color: AppColors.textPrimary),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: Text(
                  spec.label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Expanded(
                child: Text(
                  spec.value,
                  textAlign: TextAlign.left,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.4,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              const Icon(
                Icons.chevron_right,
                size: 20,
                color: AppColors.textSecondary,
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final product = viewModel.product!;
    final safeAreaBottom = MediaQuery.of(context).padding.bottom;

    final fabricSpec = product.specifications
        .where((s) => s.label.toLowerCase() == 'fabric')
        .firstOrNull;
    final fitSpec = product.specifications
        .where((s) => s.label.toLowerCase() == 'fit')
        .firstOrNull;
    final careSpec = product.specifications
        .where((s) => s.label.toLowerCase() == 'care')
        .firstOrNull;

    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ClothingProductGallery(
                  gallery: product.gallery,
                  activeIndex: viewModel.activeGalleryIndex,
                  onThumbnailTap: viewModel.setActiveGalleryIndex,
                  experienceType: product.experienceType,
                ),
                const SizedBox(height: 24),
                ProductTitleBlock(product: product),
                const SizedBox(height: 16),
                ExpandableProductDescription(description: product.description),
                const SizedBox(height: 16),
                if (fabricSpec != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: _buildSpecRow(fabricSpec, Icons.layers_outlined),
                  ),
                const SizedBox(height: 16),
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
                if (product.availableSizes.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: ProductSizeSelector(
                      availableSizes: product.availableSizes,
                      selectedSize: viewModel.selectedSize,
                      onSizeSelected: viewModel.selectSize,
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if (fitSpec != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: _buildSpecRow(
                      fitSpec,
                      Icons.accessibility_new_outlined,
                    ),
                  ),
                if (careSpec != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    child: Column(
                      children: [
                        _buildSpecRow(
                          careSpec,
                          Icons.local_laundry_service_outlined,
                        ),
                        const Divider(
                          height: 1,
                          color: AppColors.neutralMediumLight,
                        ),
                      ],
                    ),
                  ),
                const SizedBox(height: 16),
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
                const SizedBox(height: 32),
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24.0),
                  child: ClothingBenefitsCard(),
                ),
                SizedBox(height: safeAreaBottom > 0 ? safeAreaBottom : 16),
              ],
            ),
          ),
        ),
        ProductDetailsBottomActions(
          experienceType: product.experienceType,
          price: product.summary.currentPrice,
          isOutOfStock: viewModel.isOutOfStock,
          hasRenderableVtoAsset: product.hasRenderableVtoAsset,
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
      ],
    );
  }
}
