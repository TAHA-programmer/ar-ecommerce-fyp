import 'dart:io';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../../core/data/category_repository.dart';
import '../../../../core/services/device_image_picker_service.dart';
import '../../../../core/services/image_picker_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/models/product/product_category.dart';
import '../viewmodels/admin_category_form_viewmodel.dart';

/// Real Add/Edit Category screen (Phase 8.8 UX follow-up), replacing the
/// former `AdminAddCategoryDialog`/`AdminEditCategoryDialog` dialogs -
/// matches `AdminProductFormView`'s exact screen conventions (plain
/// `Scaffold`+`AppBar`, not `AdminShell`, since this is a pushed sub-screen;
/// discard-changes `PopScope`; bottom action bar; each field group in its
/// own lime-bordered white card, the same "every information group is its
/// own card, never loose text" convention already established across Admin
/// screens - see `AdminProductFormView`'s collapsible section cards and
/// Admin Order Detail's card-based sections).
class AdminCategoryFormView extends StatelessWidget {
  final String? categoryId; // null for Add, String for Edit

  const AdminCategoryFormView({super.key, this.categoryId});

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider(
      create: (context) => AdminCategoryFormViewModel(
        categoryRepository: context.read<CategoryRepository>(),
        storageService: context.read<StorageService>(),
        initialCategoryId: categoryId,
      ),
      child: const _AdminCategoryFormContent(),
    );
  }
}

class _AdminCategoryFormContent extends StatefulWidget {
  const _AdminCategoryFormContent();

  @override
  State<_AdminCategoryFormContent> createState() =>
      _AdminCategoryFormContentState();
}

class _AdminCategoryFormContentState extends State<_AdminCategoryFormContent> {
  final ImagePickerService _imagePickerService = DeviceImagePickerService();

  Future<void> _pickImage(AdminCategoryFormViewModel viewModel) async {
    final path = await _imagePickerService.pickImageFromGallery();
    if (path == null) return;
    viewModel.setImageFile(File(path));
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

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminCategoryFormViewModel>();

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
            viewModel.isEditMode ? 'Edit Category' : 'Add Category',
            style: AppTypography.title,
          ),
        ),
        body: Stack(
          children: [
            ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                _card(child: _buildNameField(viewModel)),
                _card(child: _buildKindField(viewModel)),
                if (viewModel.isEditMode)
                  _card(child: _buildKeyField(viewModel)),
                _card(child: _buildImageField(context, viewModel)),
                _card(child: _buildStatusField(viewModel)),
              ],
            ),
            if (viewModel.isSaving)
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

  /// One field group as its own lime-bordered white card - the same
  /// container style used for `AdminProductFormView`'s collapsible sections
  /// and `AdminCategoryCard`/`AdminProductCard`'s list cards throughout this
  /// app: white fill, 12px radius, a single `AppColors.primary` border.
  Widget _card({required Widget child}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary),
      ),
      child: child,
    );
  }

  Widget _fieldLabel(String text) => Text(
    text,
    style: AppTypography.bodySmall.copyWith(fontWeight: FontWeight.bold),
  );

  /// Same `OutlineInputBorder`/radius-8/lime-border shape
  /// `AdminProductFormView._buildTextField`/`_buildDropdown` already use,
  /// reused here so every Admin form field looks consistent app-wide.
  InputDecoration _fieldDecoration({String? hintText}) {
    return InputDecoration(
      hintText: hintText,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
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
    );
  }

  Widget _buildNameField(AdminCategoryFormViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Name'),
        const SizedBox(height: 8),
        TextField(
          controller: viewModel.nameController,
          maxLength: 60,
          style: AppTypography.bodyMedium,
          decoration: _fieldDecoration(hintText: 'e.g. Outdoor Furniture'),
        ),
        const SizedBox(height: 6),
        Text(
          'The category name shown to customers and Admin. You can create '
          'as many categories as you need - this is not limited to the '
          'Kind list below.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildKindField(AdminCategoryFormViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Kind'),
        const SizedBox(height: 8),
        if (viewModel.isEditMode)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
            decoration: BoxDecoration(
              color: AppColors.neutralLight.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.neutralLight),
            ),
            child: Text(viewModel.kind.label, style: AppTypography.bodyMedium),
          )
        else
          DropdownButtonFormField<ProductCategory>(
            initialValue: viewModel.kind,
            isExpanded: true,
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textPrimary,
            ),
            decoration: _fieldDecoration(),
            items: AdminCategoryFormViewModel.selectableKinds
                .map((k) => DropdownMenuItem(value: k, child: Text(k.label)))
                .toList(),
            onChanged: (value) {
              if (value != null) viewModel.setKind(value);
            },
          ),
        const SizedBox(height: 6),
        Text(
          viewModel.isEditMode
              ? 'Kind cannot be changed after a category is created.'
              : 'Not another category field - Kind controls which AR '
                    'experience this category is eligible for (Room AR vs. '
                    'Virtual Try-On). Pick whichever of these five it '
                    'behaves most like. This cannot be changed later.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildKeyField(AdminCategoryFormViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Key'),
        const SizedBox(height: 8),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: AppColors.neutralLight.withValues(alpha: 0.3),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.neutralLight),
          ),
          child: Text(
            viewModel.original?.key ?? '',
            style: AppTypography.bodyMedium,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          'A unique identifier generated automatically from the name when '
          'this category was created. It never changes, even if you rename '
          'the category above.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildImageField(
    BuildContext context,
    AdminCategoryFormViewModel viewModel,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _fieldLabel('Image'),
        const SizedBox(height: 8),
        Row(
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                border: Border.all(color: AppColors.primary, width: 1.5),
                borderRadius: BorderRadius.circular(8),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6.5),
                child: viewModel.imageFile != null
                    ? Image.file(viewModel.imageFile!, fit: BoxFit.cover)
                    : (!viewModel.removeImage &&
                          viewModel.existingImageUrl.isNotEmpty)
                    ? Image.network(
                        viewModel.existingImageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const Icon(
                          Icons.broken_image_outlined,
                          color: AppColors.textSecondary,
                        ),
                      )
                    : Container(
                        color: AppColors.neutralLight.withValues(alpha: 0.4),
                        child: const Icon(
                          Icons.category_outlined,
                          color: AppColors.textSecondary,
                        ),
                      ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Wrap(
                spacing: 4,
                children: [
                  OutlinedButton(
                    onPressed: () => _pickImage(viewModel),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: Text(viewModel.hasImage ? 'Replace' : 'Add Image'),
                  ),
                  if (viewModel.hasImage)
                    TextButton(
                      onPressed: viewModel.clearImage,
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.error,
                      ),
                      child: const Text('Remove'),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Required. Shown as this category\'s thumbnail throughout the '
          'app. JPG, PNG, or WebP, up to 5MB.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildStatusField(AdminCategoryFormViewModel viewModel) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            _fieldLabel('Status'),
            Row(
              children: [
                Text(
                  viewModel.isActive ? 'Active' : 'Inactive',
                  style: AppTypography.bodySmall.copyWith(
                    color: viewModel.isActive
                        ? AppColors.success
                        : AppColors.textSecondary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Switch(
                  value: viewModel.isActive,
                  activeTrackColor: AppColors.primary,
                  onChanged: viewModel.setActive,
                ),
              ],
            ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Inactive categories are hidden from customers but stay visible '
          'to Admin.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomActions(
    BuildContext context,
    AdminCategoryFormViewModel viewModel,
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
            TextButton(
              onPressed: viewModel.isSaving
                  ? null
                  : () => Navigator.maybePop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: AppColors.textSecondary),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton(
                onPressed: viewModel.isSaving
                    ? null
                    : () async {
                        if (await viewModel.save(context) && context.mounted) {
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
                child: Text(viewModel.isEditMode ? 'Update' : 'Add'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
