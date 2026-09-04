import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../../core/data/category_repository.dart';
import '../../../../core/models/product/product_category.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/utils/stock_status.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/widgets/product_image_view.dart';
import '../viewmodels/admin_inventory_viewmodel.dart';
import 'stock_quantity_control.dart';

class AdminInventoryProductCard extends StatefulWidget {
  final ProductModel product;

  const AdminInventoryProductCard({super.key, required this.product});

  @override
  State<AdminInventoryProductCard> createState() =>
      _AdminInventoryProductCardState();
}

class _AdminInventoryProductCardState extends State<AdminInventoryProductCard> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    final viewModel = context.read<AdminInventoryViewModel>();
    _controller = TextEditingController(
      text: viewModel.pendingQuantityFor(widget.product.id).toString(),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _syncControllerTo(int quantity) {
    final text = quantity.toString();
    if (_controller.text == text) return;
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  Color _statusColor(StockStatus status) {
    switch (status) {
      case StockStatus.inStock:
        return AppColors.success;
      case StockStatus.lowStock:
        return AppColors.warning;
      case StockStatus.outOfStock:
        return AppColors.error;
    }
  }

  Future<void> _handleSave(AdminInventoryViewModel viewModel) async {
    final productId = widget.product.id;
    final saved = await viewModel.saveProduct(productId);
    if (!mounted) return;
    if (saved) {
      _syncControllerTo(viewModel.pendingQuantityFor(productId));
      AppToast.success(context, 'Stock updated successfully');
    } else {
      final error = viewModel.errorFor(productId);
      if (error != null) {
        AppToast.error(context, error);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminInventoryViewModel>();
    final product = widget.product;
    final id = product.id;

    final categoryName =
        context.watch<CategoryRepository>().byId(product.categoryId)?.name ??
        product.categoryKind.label;
    final error = viewModel.errorFor(id);
    final isDirty = viewModel.hasPendingChange(id);
    final status = viewModel.stockStatusFor(id);
    final lastUpdated = viewModel.lastUpdatedFor(id);

    return Container(
      key: ValueKey('inventory_card_$id'),
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.white,
        border: Border.all(color: AppColors.primary, width: 1.5),
        borderRadius: AppRadii.largeBorder,
      ),
      padding: const EdgeInsets.all(AppSpacing.s),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  border: Border.all(color: AppColors.primary, width: 1.5),
                  borderRadius: AppRadii.smallBorder,
                ),
                clipBehavior: Clip.antiAlias,
                child: ProductImageView(
                  imageRef: product.mainImage,
                  fit: BoxFit.cover,
                ),
              ),
              const SizedBox(width: AppSpacing.s),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      product.title,
                      style: AppTypography.bodyMedium.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      '$categoryName · SKU: ${product.sku}',
                      style: AppTypography.bodySmall.copyWith(
                        color: AppColors.textSecondary,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _StatusPill(label: status.label, color: _statusColor(status)),
            ],
          ),
          const SizedBox(height: AppSpacing.s),
          const Divider(height: 1, color: AppColors.neutralLight),
          const SizedBox(height: AppSpacing.s),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              StockQuantityControl(
                controller: _controller,
                hasError: error != null,
                onDecrement: () {
                  viewModel.decrementQuantity(id);
                  _syncControllerTo(viewModel.pendingQuantityFor(id));
                },
                onIncrement: () {
                  viewModel.incrementQuantity(id);
                  _syncControllerTo(viewModel.pendingQuantityFor(id));
                },
                onChanged: (value) =>
                    viewModel.setPendingQuantityFromText(id, value),
              ),
              const SizedBox(width: AppSpacing.s),
              _SaveButton(
                hasError: error != null,
                isDirty: isDirty,
                onPressed: error != null ? null : () => _handleSave(viewModel),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Min: ${viewModel.lowStockThreshold}',
                  style: AppTypography.caption,
                ),
              ),
              Expanded(
                child: Text(
                  lastUpdated == null
                      ? 'Last updated: —'
                      : 'Last updated: ${DateFormat('MMM dd, yyyy • hh:mm a').format(lastUpdated)}',
                  textAlign: TextAlign.end,
                  style: AppTypography.caption,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (error != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                const Icon(
                  Icons.error_outline,
                  size: 14,
                  color: AppColors.error,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    error,
                    style: AppTypography.caption.copyWith(
                      color: AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final Color color;

  const _StatusPill({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: AppRadii.smallBorder,
      ),
      child: Text(
        label,
        style: AppTypography.bodySmall.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _SaveButton extends StatelessWidget {
  final bool hasError;
  final bool isDirty;
  final VoidCallback? onPressed;

  const _SaveButton({
    required this.hasError,
    required this.isDirty,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final Color color = hasError ? AppColors.error : AppColors.primary;

    return OutlinedButton.icon(
      key: const Key('inventory_save_button'),
      onPressed: onPressed,
      icon: Icon(
        hasError ? Icons.error_outline : Icons.check_circle_outline,
        size: 16,
        color: color,
      ),
      label: const Text('Save'),
      style: OutlinedButton.styleFrom(
        foregroundColor: color,
        backgroundColor: isDirty && !hasError
            ? AppColors.primary.withValues(alpha: 0.08)
            : Colors.transparent,
        side: BorderSide(color: color, width: hasError ? 1.5 : 1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        minimumSize: const Size(0, 40),
      ),
    );
  }
}
