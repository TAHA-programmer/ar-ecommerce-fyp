import 'dart:io';

import 'package:flutter/material.dart';
import '../../../../core/data/category_repository.dart';
import '../../../../core/data/firestore_category_repository.dart'
    show categoryNameMaxLength, slugifyCategoryName;
import '../../../../core/models/category/commerce_category_model.dart';
import '../../../../core/models/product/product_category.dart';
import '../../../../core/services/firebase_storage_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/utils/image_upload_validator.dart';
import '../../../../core/utils/unique_object_name.dart';
import '../../../../core/widgets/feedback/app_toast.dart';

/// Dedicated Add/Edit Category form ViewModel - mirrors
/// `AdminProductFormViewModel`'s split from `AdminProductManagementViewModel`
/// exactly: the list screen (search/filter/sort/delete) and the form screen
/// (create/update) are deliberately separate ViewModels. This split is not
/// just tidiness - it's what lets the form be a real, independently-routed
/// screen (`AdminCategoryFormView`) rather than a dialog. A dialog built via
/// `showDialog` is pushed onto the app's ROOT navigator, outside whatever
/// route-local provider scope a `ChangeNotifierProvider` created inside
/// `AdminProductsView.build()` lives in - exactly the bug the previous
/// dialog-based `AdminAddCategoryDialog`/`AdminEditCategoryDialog` hit and
/// had to work around by threading the list screen's ViewModel in through a
/// constructor parameter. A real routed screen has the same problem in the
/// other direction if it depended on `AdminProductManagementViewModel`
/// (which is intentionally scoped to the products/categories list route,
/// not registered app-wide) - so this ViewModel depends only on
/// [CategoryRepository]/[StorageService], both real app-wide providers,
/// exactly like `AdminProductFormViewModel` depends only on
/// `CommerceDatabase`/`StorageService`, never on
/// `AdminProductManagementViewModel`.
class AdminCategoryFormViewModel extends ChangeNotifier {
  final CategoryRepository categoryRepository;
  final StorageService storageService;
  final String? initialCategoryId;

  AdminCategoryFormViewModel({
    required this.categoryRepository,
    StorageService? storageService,
    this.initialCategoryId,
  }) : storageService = storageService ?? FirebaseStorageService() {
    _init();
  }

  bool get isEditMode => initialCategoryId != null;

  CommerceCategoryModel? _original;
  CommerceCategoryModel? get original => _original;

  String? _error;
  String? get error => _error;

  final nameController = TextEditingController();

  static final List<ProductCategory> selectableKinds = ProductCategory.values
      .where((k) => k != ProductCategory.all)
      .toList();

  ProductCategory _kind = selectableKinds.first;
  ProductCategory get kind => _kind;

  bool _isActive = true;
  bool get isActive => _isActive;

  /// Existing image URL (edit mode only) - `''` if the category has none.
  String _existingImageUrl = '';
  String get existingImageUrl => _existingImageUrl;

  File? _imageFile;
  File? get imageFile => _imageFile;

  bool _removeImage = false;
  bool get removeImage => _removeImage;

  bool _isSaving = false;
  bool get isSaving => _isSaving;

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  void _init() {
    nameController.addListener(_markDirty);
    if (!isEditMode) return;

    try {
      _original = categoryRepository.categories.firstWhere(
        (c) => c.categoryId == initialCategoryId,
      );
    } catch (_) {
      _error = 'Category not found.';
      return;
    }
    nameController.text = _original!.name;
    _kind = _original!.kind;
    _isActive = _original!.isActive;
    _existingImageUrl = _original!.imageUrl;
    // Populating from the loaded category is not a user edit.
    _hasUnsavedChanges = false;
  }

  void _markDirty() {
    _hasUnsavedChanges = true;
  }

  bool get hasImage =>
      _imageFile != null || (!_removeImage && _existingImageUrl.isNotEmpty);

  void setKind(ProductCategory value) {
    if (isEditMode) return; // kind is permanently immutable after creation
    _kind = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setActive(bool value) {
    _isActive = value;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setImageFile(File file) {
    _imageFile = file;
    _removeImage = false;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void clearImage() {
    _imageFile = null;
    _removeImage = true;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  bool _isDuplicateName(String trimmedName) {
    final lower = trimmedName.toLowerCase();
    return categoryRepository.categories.any(
      (c) =>
          c.categoryId != initialCategoryId &&
          c.name.trim().toLowerCase() == lower,
    );
  }

  String? _validateName(String trimmedName) {
    if (trimmedName.isEmpty) return 'Please enter a category name.';
    if (trimmedName.length > categoryNameMaxLength) {
      return 'Category name must be $categoryNameMaxLength characters or fewer.';
    }
    return null;
  }

  /// Creates or updates the category, mirroring the exact validate-before-
  /// upload ordering and image-lifecycle guarantees previously implemented
  /// on `AdminProductManagementViewModel` (moved here wholesale, not
  /// duplicated - that ViewModel no longer has create/update methods at
  /// all, matching `AdminProductManagementViewModel`/`AdminProductFormViewModel`'s
  /// existing split for products).
  Future<bool> save(BuildContext context) async {
    if (_isSaving) return false;

    final trimmedName = nameController.text.trim();
    final nameError = _validateName(trimmedName);
    if (nameError != null) {
      if (context.mounted) AppToast.error(context, nameError);
      return false;
    }
    if (_isDuplicateName(trimmedName)) {
      if (context.mounted) {
        AppToast.error(
          context,
          'A category with this name already exists. Please use a different name.',
        );
      }
      return false;
    }
    // A category image is compulsory (both Add and Edit) - a category with
    // no photo falls back to a generic themed image on Home, which is a
    // usability compromise, not something a real category should ship
    // without. Applies on every save, not just create, so an existing
    // category can't be edited back into an image-less state either.
    if (!hasImage) {
      if (context.mounted) {
        AppToast.error(context, 'Please add a category image.');
      }
      return false;
    }

    String? newCategoryIdForUpload = initialCategoryId;
    if (!isEditMode) {
      if (_kind == ProductCategory.all) {
        if (context.mounted) {
          AppToast.error(context, 'Please choose a specific category type.');
        }
        return false;
      }
      final slug = slugifyCategoryName(trimmedName);
      if (slug.isEmpty) {
        if (context.mounted) {
          AppToast.error(context, 'Please enter a valid category name.');
        }
        return false;
      }
      newCategoryIdForUpload = slug;
    }

    _isSaving = true;
    notifyListeners();

    String? uploadedUrlThisSave;
    try {
      if (isEditMode) {
        await _saveEdit(context, trimmedName, newCategoryIdForUpload!, (url) {
          uploadedUrlThisSave = url;
        });
      } else {
        await _saveCreate(context, trimmedName, newCategoryIdForUpload!, (url) {
          uploadedUrlThisSave = url;
        });
      }
      _hasUnsavedChanges = false;
      if (context.mounted) {
        AppToast.success(
          context,
          isEditMode
              ? 'Category updated successfully'
              : 'Category added successfully',
        );
      }
      return true;
    } catch (e) {
      if (uploadedUrlThisSave != null) {
        try {
          await storageService.deleteCategoryImageByUrl(uploadedUrlThisSave!);
        } catch (_) {
          // Best-effort only.
        }
      }
      if (context.mounted) AppToast.error(context, _errorMessage(e));
      return false;
    } finally {
      _isSaving = false;
      notifyListeners();
    }
  }

  Future<void> _saveCreate(
    BuildContext context,
    String trimmedName,
    String categoryId,
    void Function(String url) onUploaded,
  ) async {
    var imageUrl = '';
    if (_imageFile != null) {
      await validateImageFileForUpload(
        _imageFile!,
        maxSizeBytes: categoryImageMaxUploadBytes,
        label: 'image',
      );
      final objectName = generateUniqueObjectName(
        extension: extensionFromPath(_imageFile!.path),
      );
      imageUrl = await storageService.uploadCategoryImage(
        categoryId: categoryId,
        objectName: objectName,
        file: _imageFile!,
      );
      onUploaded(imageUrl);
    }

    await categoryRepository.addCategory(
      name: trimmedName,
      kind: _kind,
      imageUrl: imageUrl,
      isActive: _isActive,
    );
  }

  Future<void> _saveEdit(
    BuildContext context,
    String trimmedName,
    String categoryId,
    void Function(String url) onUploaded,
  ) async {
    final original = _original!;
    var newImageUrl = original.imageUrl;
    if (_imageFile != null) {
      await validateImageFileForUpload(
        _imageFile!,
        maxSizeBytes: categoryImageMaxUploadBytes,
        label: 'image',
      );
      final objectName = generateUniqueObjectName(
        extension: extensionFromPath(_imageFile!.path),
      );
      newImageUrl = await storageService.uploadCategoryImage(
        categoryId: categoryId,
        objectName: objectName,
        file: _imageFile!,
      );
      onUploaded(newImageUrl);
    } else if (_removeImage) {
      newImageUrl = '';
    }

    final updated = original.copyWith(
      name: trimmedName,
      imageUrl: newImageUrl,
      isActive: _isActive,
    );
    await categoryRepository.updateCategory(updated);

    // Only now, with the Firestore write confirmed successful, clean up the
    // previous image object (if it was replaced or removed) - never before,
    // mirroring the exact ordering the previous dialog implementation used.
    final previousImageChanged =
        (_imageFile != null || _removeImage) &&
        original.imageUrl.isNotEmpty &&
        original.imageUrl != newImageUrl;
    if (previousImageChanged) {
      try {
        await storageService.deleteCategoryImageByUrl(original.imageUrl);
      } catch (_) {
        // Best-effort only.
      }
    }
  }

  String _errorMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is ImageValidationException) return error.message;
    if (error is StorageServiceException) return error.message;
    return 'Something went wrong. Please try again.';
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }
}
