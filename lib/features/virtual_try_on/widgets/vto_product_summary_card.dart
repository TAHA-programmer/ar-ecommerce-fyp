import 'package:flutter/material.dart';
import '../../product_details/models/product_detail_model.dart';
import '../../product_details/widgets/product_size_selector.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/product_image_view.dart';

/// Product summary + variant selection for the Virtual Try-On setup screen
/// (Phase 9.3 Stage 5) — one layout regardless of [ProductVtoModelType].
///
/// The colour selector only offers colours the product actually sells
/// ([ProductDetailModel.availableColors]); a colour with no configured
/// try-on garment asset ([colorHasPreview] false) is shown, visibly marked
/// "No preview", and disabled for THIS flow — it may still be a perfectly
/// valid purchase colour, so it is never hidden entirely.
class VtoProductSummaryCard extends StatelessWidget {
  final ProductDetailModel product;
  final ProductColorOption? selectedColor;
  final ProductSize? selectedSize;
  final bool Function(ProductColorOption) colorHasPreview;
  final ValueChanged<ProductColorOption> onColorSelected;
  final ValueChanged<ProductSize> onSizeSelected;

  const VtoProductSummaryCard({
    super.key,
    required this.product,
    required this.selectedColor,
    required this.selectedSize,
    required this.colorHasPreview,
    required this.onColorSelected,
    required this.onSizeSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neutralLight),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.neutralLight),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: ProductImageView(
                    imageRef: product.summary.image,
                    width: 80,
                    height: 100,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.summary.title,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      product.summary.currentPrice,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.primaryDark,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(
                          product.stockQuantity > 0
                              ? Icons.check_circle
                              : Icons.remove_circle_outline,
                          color: product.stockQuantity > 0
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          product.stockQuantity > 0
                              ? 'In Stock'
                              : 'Out of Stock',
                          style: AppTypography.bodySmall.copyWith(
                            color: AppColors.textPrimary,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(height: 1, color: AppColors.neutralLight),
          const SizedBox(height: 16),
          if (product.availableColors.isNotEmpty) ...[
            _ColorSelector(
              colors: product.availableColors,
              selected: selectedColor,
              hasPreview: colorHasPreview,
              onSelected: onColorSelected,
            ),
            const SizedBox(height: 16),
          ],
          if (product.availableSizes.isNotEmpty)
            ProductSizeSelector(
              availableSizes: product.availableSizes,
              selectedSize: selectedSize,
              onSizeSelected: onSizeSelected,
            ),
        ],
      ),
    );
  }
}

class _ColorSelector extends StatelessWidget {
  final List<ProductColorOption> colors;
  final ProductColorOption? selected;
  final bool Function(ProductColorOption) hasPreview;
  final ValueChanged<ProductColorOption> onSelected;

  const _ColorSelector({
    required this.colors,
    required this.selected,
    required this.hasPreview,
    required this.onSelected,
  });

  Color _swatch(ProductColorOption option) {
    switch (option) {
      case ProductColorOption.beige:
        return const Color(0xFFE5D3C1);
      case ProductColorOption.gray:
        return Colors.grey;
      case ProductColorOption.black:
        return Colors.black;
      case ProductColorOption.brown:
        return Colors.brown;
      case ProductColorOption.blue:
        return const Color(0xFF6A8EAE);
      case ProductColorOption.green:
        return Colors.green;
      case ProductColorOption.pink:
        return Colors.pinkAccent;
    }
  }

  String _name(ProductColorOption option) {
    switch (option) {
      case ProductColorOption.beige:
        return 'Beige';
      case ProductColorOption.gray:
        return 'Gray';
      case ProductColorOption.black:
        return 'Black';
      case ProductColorOption.brown:
        return 'Brown';
      case ProductColorOption.blue:
        return 'Sky Blue';
      case ProductColorOption.green:
        return 'Green';
      case ProductColorOption.pink:
        return 'Pink';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
            ),
            children: [
              const TextSpan(text: 'Colour for preview: '),
              TextSpan(
                text: selected != null ? _name(selected!) : '',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: colors.map((color) {
            final isSelected = color == selected;
            final eligible = hasPreview(color);
            return GestureDetector(
              onTap: eligible ? () => onSelected(color) : null,
              child: Opacity(
                opacity: eligible ? 1 : 0.4,
                child: Column(
                  children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Container(
                          width: 30,
                          height: 30,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _swatch(color),
                            border: Border.all(
                              color: isSelected
                                  ? AppColors.primary
                                  : AppColors.neutralMediumLight,
                              width: isSelected ? 2 : 1,
                            ),
                          ),
                        ),
                        if (isSelected)
                          Positioned(
                            bottom: -2,
                            right: -2,
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 10,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (!eligible) ...[
                      const SizedBox(height: 2),
                      Text(
                        'No preview',
                        style: AppTypography.caption.copyWith(fontSize: 9),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
