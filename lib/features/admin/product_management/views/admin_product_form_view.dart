import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/widgets/feedback/app_toast.dart';
import 'package:twin_ar/core/models/product/product_publication_status.dart';
import '../../../../core/data/category_repository.dart';
import '../../../../core/data/commerce_database.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/models/category/commerce_category_model.dart';
import '../../../../core/models/product/product_category.dart';
import '../../../../core/models/product/product_color_option.dart';
import '../../../../core/models/product/product_experience_type.dart';
import '../../../../core/models/product/product_image_ref.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/models/product/product_size.dart';
import '../../../../core/models/product/product_vto_model_type.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/product_image_view.dart';
import '../viewmodels/admin_product_form_viewmodel.dart';
import '../widgets/admin_image_picker_sheet.dart';
import '../../ar_media_management/viewmodels/ar_media_management_viewmodel.dart';

class AdminProductFormView extends StatelessWidget {
  final String? productId; // null for Add, String for Edit

  const AdminProductFormView({super.key, this.productId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (_) => AdminProductFormViewModel(
        database: context.read<CommerceDatabase>(),
        categoryRepository: context.read<CategoryRepository>(),
        storageService: context.read<StorageService>(),
        initialProductId: productId,
      ),
      child: const _AdminProductFormContent(),
    );
  }
}

class _AdminProductFormContent extends StatelessWidget {
  const _AdminProductFormContent();

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminProductFormViewModel>();

    if (viewModel.error != null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(child: Text(viewModel.error!)),
      );
    }

    return PopScope(
      canPop: !viewModel.hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldPop = await _showDiscardDialog(context);
        if (shouldPop && context.mounted) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: AppBar(
          title: Text(
            viewModel.isEditMode ? 'Edit Product' : 'Add Product',
            style: AppTypography.title,
          ),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.only(
                bottom: 100,
              ), // Space for bottom bar
              children: [
                _buildSection(
                  title: '1. Basic Information',
                  isExpanded: viewModel.basicInfoExpanded,
                  onToggle: viewModel.toggleBasicInfo,
                  child: _buildBasicInfoFields(context, viewModel),
                ),
                _buildSection(
                  title: '2. Product Details',
                  isExpanded: viewModel.productDetailsExpanded,
                  onToggle: viewModel.toggleProductDetails,
                  child: _buildProductDetailsFields(viewModel),
                ),
                _buildSection(
                  title: '3. Product Images',
                  isExpanded: viewModel.productImagesExpanded,
                  onToggle: viewModel.toggleProductImages,
                  child: _buildProductImagesField(context, viewModel),
                ),
                _buildSection(
                  title: '4. AR Type',
                  isExpanded: viewModel.arTypeExpanded,
                  onToggle: viewModel.toggleArType,
                  child: _buildArTypeFields(context, viewModel),
                ),
                const SizedBox(height: 24),
              ],
            ),
            if (viewModel.isLoading)
              const Positioned.fill(
                child: ColoredBox(
                  color: Colors.black26,
                  child: Center(child: CircularProgressIndicator()),
                ),
              ),
          ],
        ),
        bottomSheet: _buildBottomActions(context, viewModel),
      ),
    );
  }

  Future<bool> _showDiscardDialog(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Discard Changes?'),
        content: const Text('Your unsaved changes will be lost.'),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Keep Editing'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text(
              'Discard',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  void _confirmUpdate(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Update Product?'),
        content: Text(
          'Are you sure you want to update\n"${viewModel.titleController.text}"?',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              if (await viewModel.updateProduct(context) && context.mounted) {
                Navigator.pop(context);
              }
            },
            child: const Text(
              'Update',
              style: TextStyle(color: AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    showDialog(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Delete Product?'),
        content: Text(
          'Are you sure you want to delete\n"${viewModel.titleController.text}"?',
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(c);
              await viewModel.deleteProduct(context);
              if (context.mounted) Navigator.pop(context);
            },
            child: const Text(
              'Delete',
              style: TextStyle(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSection({
    required String title,
    required bool isExpanded,
    required VoidCallback onToggle,
    required Widget child,
  }) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
            child: Padding(
              padding: const EdgeInsets.all(16.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    title,
                    style: AppTypography.bodyLarge.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Icon(
                    isExpanded ? Icons.expand_less : Icons.expand_more,
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (isExpanded) ...[
                  const Divider(height: 1, color: AppColors.primary),
                  Padding(padding: const EdgeInsets.all(16.0), child: child),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBasicInfoFields(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildTextField('Product Name', viewModel.titleController),
        const SizedBox(height: 16),
        _buildCategoryField(context, viewModel),
        const SizedBox(height: 16),
        _buildTextField('Subcategory', viewModel.subcategoryController),
        const SizedBox(height: 16),
        _buildTextField(
          'Description',
          viewModel.descriptionController,
          maxLines: 4,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: _buildTextField(
                'Price (Rs)',
                viewModel.priceController,
                keyboardType: TextInputType.number,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _buildTextField(
                'Discount Price (Rs)',
                viewModel.discountPriceController,
                keyboardType: TextInputType.number,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        _buildTextField(
          'Stock Quantity',
          viewModel.stockController,
          keyboardType: TextInputType.number,
        ),
        const SizedBox(height: 16),
        Text(
          'Status',
          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Is Active', style: AppTypography.bodySmall),
              Switch(
                value: viewModel.isActive,
                onChanged: viewModel.setIsActive,
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.primary),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      'Feature on Home',
                      style: AppTypography.bodySmall,
                    ),
                  ),
                  Switch(
                    value: viewModel.isFeatured,
                    onChanged: viewModel.setIsFeatured,
                    activeThumbColor: AppColors.primary,
                  ),
                ],
              ),
              if (viewModel.isFeatured) ...[
                const SizedBox(height: 4),
                _buildTextField(
                  'Feature order (positive number, lower shows first — '
                  'blank uses the default)',
                  viewModel.featuredRankController,
                  keyboardType: TextInputType.number,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                ),
                const SizedBox(height: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  /// Category picker (Phase 8.8b) - sourced live from `CategoryRepository`
  /// instead of the fixed `ProductCategory` enum, so a brand-new
  /// Admin-created category shows up here immediately. Handles every
  /// CategoryRepository edge case explicitly: loading, error, zero active
  /// categories, and an existing product's category having gone
  /// inactive/missing - never silently defaults to an arbitrary category.
  Widget _buildCategoryField(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    if (viewModel.categoriesLoading) {
      return _buildCategoryStateBanner(
        icon: Icons.hourglass_empty,
        message: 'Loading categories…',
      );
    }
    if (viewModel.categoriesUnavailable) {
      return _buildCategoryStateBanner(
        icon: Icons.error_outline,
        message: 'Could not load categories. Please try again.',
        isError: true,
      );
    }
    if (viewModel.selectedCategoryMissing) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildCategoryStateBanner(
            icon: Icons.error_outline,
            message:
                "This product's category was deleted. Please choose a new one below.",
            isError: true,
          ),
          const SizedBox(height: 8),
          _buildCategoryDropdown(context, viewModel),
        ],
      );
    }
    if (viewModel.selectableCategories.isEmpty) {
      return _buildCategoryStateBanner(
        icon: Icons.category_outlined,
        message:
            'No active categories available - activate or create one '
            'first.',
        isError: true,
      );
    }
    return _buildCategoryDropdown(context, viewModel);
  }

  Widget _buildCategoryDropdown(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    return _buildDropdown<CommerceCategoryModel>(
      label: 'Category',
      value: viewModel.resolvedCategory,
      items: viewModel.selectableCategories
          .map(
            (c) => DropdownMenuItem(
              value: c,
              child: Text(c.isActive ? c.name : '${c.name} (inactive)'),
            ),
          )
          .toList(),
      onChanged: (c) async {
        if (c != null) await viewModel.requestCategoryChange(context, c);
      },
    );
  }

  Widget _buildCategoryStateBanner({
    required IconData icon,
    required String message,
    bool isError = false,
  }) {
    final color = isError ? AppColors.error : AppColors.textSecondary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: color),
        borderRadius: BorderRadius.circular(8),
        color: color.withValues(alpha: 0.05),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: AppTypography.bodySmall.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductDetailsFields(AdminProductFormViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Available Colors',
          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ProductColorOption.values.map((c) {
            final isSelected = viewModel.availableColors.contains(c);
            return FilterChip(
              label: Text(c.name, style: AppTypography.bodySmall),
              selected: isSelected,
              selectedColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (_) => viewModel.toggleColor(c),
            );
          }).toList(),
        ),
        const SizedBox(height: 16),
        if (viewModel.categoryKind == ProductCategory.clothing) ...[
          Text(
            'Available Sizes',
            style: AppTypography.bodySmall.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: ProductSize.values.map((s) {
              final isSelected = viewModel.availableSizes.contains(s);
              return FilterChip(
                label: Text(
                  s.name.toUpperCase(),
                  style: AppTypography.bodySmall,
                ),
                selected: isSelected,
                selectedColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                onSelected: (_) => viewModel.toggleSize(s),
              );
            }).toList(),
          ),
          const SizedBox(height: 16),
        ],
        _buildTextField(
          viewModel.categoryKind == ProductCategory.clothing
              ? 'Fabric'
              : 'Material',
          TextEditingController(text: viewModel.materialOrFabric),
          onChanged: viewModel.updateMaterialOrFabric,
        ),
        const SizedBox(height: 16),
        if (viewModel.categoryKind == ProductCategory.clothing) ...[
          _buildTextField(
            'Fit Info',
            TextEditingController(text: viewModel.fitInfo),
            onChanged: viewModel.updateFitInfo,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Care Instructions',
            TextEditingController(text: viewModel.careInstructions),
            onChanged: viewModel.updateCareInstructions,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            'Size Guide',
            TextEditingController(text: viewModel.sizeGuide),
            onChanged: viewModel.updateSizeGuide,
          ),
        ] else ...[
          _buildTextField(
            'Dimensions',
            TextEditingController(text: viewModel.dimensions),
            onChanged: viewModel.updateDimensions,
          ),
        ],
      ],
    );
  }

  Widget _buildProductImagesField(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Images (Min 1, Max 5)',
          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            ...viewModel.images.map((img) {
              final isPrimary = viewModel.primaryImage?.path == img.path;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () => viewModel.setPrimaryImage(img),
                    child: Container(
                      width: 80,
                      height: 80,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isPrimary
                              ? AppColors.primary
                              : AppColors.neutralLight,
                          width: isPrimary ? 2 : 1,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: ProductImageView(imageRef: img, fit: BoxFit.cover),
                    ),
                  ),
                  Positioned(
                    right: -8,
                    top: -8,
                    child: GestureDetector(
                      onTap: () => viewModel.removeImage(img),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.error,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.close,
                          size: 14,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                  if (isPrimary)
                    Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      child: Container(
                        color: AppColors.primary,
                        padding: const EdgeInsets.symmetric(vertical: 2),
                        child: const Text(
                          'PRIMARY',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  if (!isPrimary)
                    Positioned(
                      bottom: 4,
                      left: 4,
                      right: 4,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          GestureDetector(
                            onTap: () => viewModel.moveImageUp(img),
                            child: const Icon(
                              Icons.chevron_left,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                          GestureDetector(
                            onTap: () => viewModel.moveImageDown(img),
                            child: const Icon(
                              Icons.chevron_right,
                              color: Colors.white,
                              size: 20,
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            }),
            if (viewModel.images.length < 5)
              GestureDetector(
                onTap: () async {
                  final newImages =
                      await showModalBottomSheet<List<ProductImageRef>>(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (c) => AdminImagePickerSheet(
                          maxAllowed: 5 - viewModel.images.length,
                        ),
                      );
                  if (newImages != null && context.mounted) {
                    viewModel.addImages(newImages, context);
                  }
                },
                child: Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: AppColors.neutralLight,
                      width: 1,
                      style: BorderStyle.solid,
                    ),
                    color: AppColors.neutralLight,
                  ),
                  child: const Icon(Icons.add, color: AppColors.textSecondary),
                ),
              ),
          ],
        ),
      ],
    );
  }

  Widget _buildArTypeFields(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildDropdown<ProductExperienceType>(
          label: 'AR Experience',
          value: viewModel.experienceType,
          items: ProductExperienceType.values
              .where((e) {
                if (e == ProductExperienceType.none) return true;
                if (viewModel.categoryKind == ProductCategory.clothing) {
                  return e == ProductExperienceType.virtualTryOn;
                } else {
                  return e == ProductExperienceType.roomAr;
                }
              })
              .map(
                (e) => DropdownMenuItem(value: e, child: Text(e.displayName)),
              )
              .toList(),
          onChanged: (e) async {
            if (e != null) {
              await viewModel.requestExperienceTypeChange(context, e);
            }
          },
        ),
        if (viewModel.experienceType == ProductExperienceType.virtualTryOn) ...[
          const SizedBox(height: 16),
          _buildDropdown<ProductVtoModelType>(
            label: 'VTO Model Type',
            value: viewModel.vtoModelType,
            hint: 'Select Model Type',
            items: ProductVtoModelType.values
                .map(
                  (e) => DropdownMenuItem(value: e, child: Text(e.displayName)),
                )
                .toList(),
            onChanged: (e) {
              if (e != null) {
                viewModel.setVtoModelType(e);
              }
            },
          ),
        ],
        if (viewModel.experienceType != ProductExperienceType.none) ...[
          const SizedBox(height: 16),
          _buildArConfigurationSummary(context, viewModel),
        ],
      ],
    );
  }

  Widget _buildArConfigurationSummary(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    final isRoomAr = viewModel.experienceType == ProductExperienceType.roomAr;
    final title = isRoomAr
        ? 'Room AR Configuration'
        : 'Virtual Try-On Configuration';
    final configured = viewModel.isCurrentArConfigured;
    // Phase 9.2 R16 — Room AR reports the production `arMetadata` contract
    // (or the pending local upload), never the retired `arModelAssetPath`.
    final String? fileName;
    if (isRoomAr) {
      final pending = viewModel.pendingArModelFilePath;
      final committed = viewModel.arMetadata?.storagePath;
      fileName = pending != null
          ? '${pending.split(RegExp(r'[/\\]')).last} (uploads on save)'
          : committed;
    } else {
      fileName = viewModel.vtoGarmentAssetPath;
    }
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: AppTypography.label),
          const SizedBox(height: 4),
          Text(
            isRoomAr
                ? 'Configure the 3D model and placement settings.'
                : 'Configure the garment asset and try-on settings.',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                configured ? Icons.check_circle : Icons.info_outline,
                size: 18,
                color: configured ? AppColors.primaryDark : AppColors.warning,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  configured ? 'Configured' : 'Configuration Required',
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          if (configured && fileName != null) ...[
            const SizedBox(height: 4),
            Text(
              fileName.split(RegExp(r'[/\\]')).last,
              style: AppTypography.caption,
            ),
          ],
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: Key(isRoomAr ? 'configure_room_ar' : 'configure_vto'),
            onPressed: () => _openArConfiguration(context, viewModel),
            icon: const Icon(Icons.arrow_forward),
            label: Text(
              '${configured ? 'Edit' : 'Configure'} ${isRoomAr ? 'Room AR' : 'Virtual Try-On'}',
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openArConfiguration(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) async {
    if (viewModel.experienceType == ProductExperienceType.virtualTryOn &&
        viewModel.vtoModelType == null) {
      AppToast.info(context, 'Select Male or Female before configuration.');
      return;
    }
    final result = await Navigator.of(context).pushNamed(
      RouteNames.adminArMedia,
      arguments: ArMediaRouteArguments.productScoped(
        viewModel.buildArConfigurationPreview(),
      ),
    );
    if (result is ProductModel) viewModel.applyArMediaConfiguration(result);
  }

  Widget _buildBottomActions(
    BuildContext context,
    AdminProductFormViewModel viewModel,
  ) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: AppColors.neutralLight)),
        boxShadow: [
          BoxShadow(
            color: Colors.black12,
            blurRadius: 4,
            offset: Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            if (!viewModel.isEditMode) ...[
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    if (await viewModel.saveDraft(context) && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: AppTypography.bodyMedium,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                  child: const Text('Save Draft'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    if (await viewModel.publish(context) && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: AppTypography.bodyMedium,
                  ),
                  child: const Text('Publish'),
                ),
              ),
            ] else if (viewModel.originalPublicationStatus ==
                ProductPublicationStatus.published) ...[
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _confirmDelete(context, viewModel),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: AppTypography.bodyMedium,
                    side: const BorderSide(color: AppColors.error),
                    foregroundColor: AppColors.error,
                  ),
                  child: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () => _confirmUpdate(context, viewModel),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: AppTypography.bodyMedium,
                  ),
                  child: const Text('Update'),
                ),
              ),
            ] else ...[
              TextButton(
                onPressed: () => Navigator.maybePop(context),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: AppColors.textSecondary),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () => _confirmDelete(context, viewModel),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: AppTypography.bodyMedium,
                    side: const BorderSide(color: AppColors.error),
                    foregroundColor: AppColors.error,
                  ),
                  child: const Text('Delete'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton(
                  onPressed: () async {
                    if (await viewModel.saveDraft(context) && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: AppTypography.bodyMedium,
                    side: const BorderSide(color: AppColors.primary),
                  ),
                  child: const Text('Save Draft'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ElevatedButton(
                  onPressed: () async {
                    if (await viewModel.publish(context) && context.mounted) {
                      Navigator.pop(context);
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: AppColors.textPrimary,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    textStyle: AppTypography.bodyMedium,
                  ),
                  child: const Text('Publish'),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTextField(
    String label,
    TextEditingController controller, {
    int maxLines = 1,
    TextInputType keyboardType = TextInputType.text,
    void Function(String)? onChanged,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          onChanged: onChanged,
          inputFormatters: inputFormatters,
          style: AppTypography.bodyMedium,
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required void Function(T?) onChanged,
    String? hint,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<T>(
          initialValue: value,
          hint: hint == null ? null : Text(hint),
          items: items,
          onChanged: onChanged,
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textPrimary,
          ),
          decoration: InputDecoration(
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 12,
            ),
          ),
        ),
      ],
    );
  }
}
