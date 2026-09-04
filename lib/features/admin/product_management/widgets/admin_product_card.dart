import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../../core/models/product/product_model.dart';
import '../../../../../core/models/product/product_category.dart';
import '../../../../../core/models/product/product_experience_type.dart';
import '../../../../../core/models/product/product_publication_status.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/theme/app_typography.dart';
import '../../../../../core/utils/currency_formatter.dart';
import '../../../../../core/widgets/product_image_view.dart';
import '../../../../../core/data/commerce_database.dart';
import '../../../../../core/data/category_repository.dart';

class AdminProductCard extends StatelessWidget {
  final ProductModel product;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const AdminProductCard({
    super.key,
    required this.product,
    required this.onEdit,
    required this.onDelete,
  });

  /// Phase 9.2 R16 — for Room AR, show whether a renderable model contract is
  /// actually attached, so "Room AR" in the admin list is never mistaken for
  /// "customers can view this in AR".
  String _getArTypeLabel(ProductModel product) {
    switch (product.experienceType) {
      case ProductExperienceType.none:
        return 'No AR';
      case ProductExperienceType.roomAr:
        if (product.hasRenderableArModel) return 'Room AR · model ready';
        if (product.hasDisabledArModel) return 'Room AR · disabled';
        return 'Room AR · no model';
      case ProductExperienceType.virtualTryOn:
        return 'Virtual Try-On';
    }
  }

  String _getStockStatus(int quantity) {
    if (quantity == 0) return 'Out of Stock';
    if (quantity <= CommerceDatabase.lowStockThreshold) return 'Low Stock';
    return 'In Stock';
  }

  Color _getStockColor(int quantity) {
    if (quantity == 0) return AppColors.error;
    if (quantity <= CommerceDatabase.lowStockThreshold) {
      return AppColors.warning;
    }
    return AppColors.success;
  }

  @override
  Widget build(BuildContext context) {
    final categoryName =
        context.watch<CategoryRepository>().byId(product.categoryId)?.name ??
        product.categoryKind.label;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: AppColors.primary, width: 1.5),
        borderRadius: BorderRadius.circular(
          12,
        ), // AppRadii.largeBorder equivalent
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Product Image
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 1.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(6.5),
                  child: ProductImageView(
                    imageRef: product.mainImage,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // Content
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: Text(
                            product.title,
                            style: AppTypography.title.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        if (product.publicationStatus ==
                            ProductPublicationStatus.draft) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: AppColors.warning.withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              'Draft',
                              style: AppTypography.bodySmall.copyWith(
                                color: AppColors.warning,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: product.isActive
                                ? AppColors.success.withValues(alpha: 0.1)
                                : AppColors.neutralLight.withValues(alpha: 0.5),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            product.isActive ? 'Active' : 'Inactive',
                            style: AppTypography.bodySmall.copyWith(
                              color: product.isActive
                                  ? AppColors.success
                                  : AppColors.textSecondary,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'SKU: ${product.sku}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      categoryName,
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1, color: AppColors.neutralLight),
          const SizedBox(height: 12),
          // Details
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _buildDetailColumn(
                  'Price',
                  CurrencyFormatter.format(product.priceAmount),
                ),
              ),
              Expanded(
                flex: 2,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12.0),
                  child: _buildDetailColumn(
                    'Stock',
                    '${product.stockQuantity} (${_getStockStatus(product.stockQuantity)})',
                    valueColor: _getStockColor(product.stockQuantity),
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: _buildDetailColumn('AR Type', _getArTypeLabel(product)),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // Actions
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              OutlinedButton.icon(
                onPressed: onEdit,
                icon: const Icon(Icons.edit, size: 16),
                label: const Text('Edit'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: AppColors.primary,
                  side: const BorderSide(color: AppColors.primary),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                ),
              ),
              const SizedBox(width: 8),
              ElevatedButton.icon(
                onPressed: onDelete,
                icon: const Icon(Icons.delete_outline, size: 16),
                label: const Text('Delete'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.error,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                  elevation: 0,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  minimumSize: const Size(0, 36),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailColumn(String label, String value, {Color? valueColor}) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: AppTypography.bodySmall.copyWith(
            fontWeight: FontWeight.w600,
            color: valueColor ?? AppColors.textPrimary,
          ),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}
