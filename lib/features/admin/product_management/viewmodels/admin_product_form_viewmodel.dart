import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import '../../../../core/data/category_repository.dart';
import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/category/commerce_category_model.dart';
import '../../../../core/models/product/product_ar_metadata.dart';
import '../../../../core/models/product/product_category.dart';
import '../../../../core/models/product/product_color_option.dart';
import '../../../../core/models/product/product_experience_type.dart';
import '../../../../core/models/product/product_image_ref.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/models/product/product_publication_status.dart';
import '../../../../core/models/product/product_size.dart';
import '../../../../core/models/product/product_specification.dart';
import '../../../../core/models/product/product_vto_model_type.dart';
import '../../../../core/services/firebase_storage_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/utils/image_upload_validator.dart';
import '../../../../core/utils/unique_object_name.dart';
import '../../../room_ar/model_delivery/glb_inspector.dart';
import '../../ar_media_management/utils/admin_glb_validator.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/constants/app_assets.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';

class AdminProductFormViewModel extends ChangeNotifier {
  final CommerceDatabase database;
  final CategoryRepository categoryRepository;
  final StorageService storageService;
  final String? initialProductId;

  /// [storageService] is an optional constructor parameter defaulting to
  /// the real [FirebaseStorageService] - mirrors this codebase's established
  /// "optional param, internal default" DI pattern (`AuthRepository?` on
  /// `AuthSessionState`, `OnboardingStore?` on `SplashViewModel`, etc.) so
  /// every existing test call site that constructs this ViewModel without a
  /// storage service keeps compiling and behaving exactly as before.
  /// [categoryRepository] has no such default (mirrors
  /// `AdminCategoryFormViewModel`'s identical `required` dependency) - there
  /// is no single "real" implementation to default to the way there is for
  /// storage, and every call site already has one available via the
  /// app-wide provider.
  AdminProductFormViewModel({
    required this.database,
    required this.categoryRepository,
    StorageService? storageService,
    this.initialProductId,
  }) : storageService = storageService ?? FirebaseStorageService() {
    _init();
    // Re-render whenever CategoryRepository's loading/error/data state
    // changes (e.g. the initial Firestore snapshot arrives after this form
    // is already open) - so the category dropdown/loading/error states stay
    // live instead of frozen at whatever CategoryRepository looked like at
    // construction time.
    categoryRepository.addListener(_onCategoryRepositoryChanged);
  }

  void _onCategoryRepositoryChanged() {
    notifyListeners();
  }

  bool get isEditMode => initialProductId != null;

  ProductModel? _originalProduct;
  ProductPublicationStatus? get originalPublicationStatus =>
      _originalProduct?.publicationStatus;

  // Controllers
  final titleController = TextEditingController();
  final subcategoryController = TextEditingController();
  final descriptionController = TextEditingController();
  final priceController = TextEditingController();
  final discountPriceController = TextEditingController();
  final stockController = TextEditingController();

  // Basic Info State - Phase 8.8b: a real categoryId reference, resolved
  // live against CategoryRepository, never a silently-defaulted enum value.
  String? _categoryId;

  bool get categoriesLoading => categoryRepository.isLoading;
  bool get categoriesUnavailable => categoryRepository.hasError;

  /// The currently-selected category, resolved live - `null` if nothing is
  /// selected yet, the category was deleted, or (rare) it's inactive on a
  /// session that can't see inactive categories. Never falls back to an
  /// arbitrary category.
  CommerceCategoryModel? get resolvedCategory =>
      _categoryId == null ? null : categoryRepository.byId(_categoryId!);

  /// `true` only when a categoryId is set but doesn't resolve to any
  /// currently-known category (deleted, or the repository hasn't loaded far
  /// enough yet to say for sure) - distinct from "nothing selected".
  bool get selectedCategoryMissing =>
      _categoryId != null && resolvedCategory == null && !categoriesLoading;

  bool get selectedCategoryInactive =>
      resolvedCategory != null && !resolvedCategory!.isActive;

  /// Dropdown source: active categories, plus the currently-resolved
  /// category if it exists but is inactive - so an existing inactive
  /// assignment stays visibly selected instead of silently disappearing
  /// from the list it needs to remain "selected" from.
  List<CommerceCategoryModel> get selectableCategories {
    final active = categoryRepository.categories
        .where((c) => c.isActive)
        .toList();
    final resolved = resolvedCategory;
    if (resolved != null &&
        !resolved.isActive &&
        !active.any((c) => c.categoryId == resolved.categoryId)) {
      return [...active, resolved];
    }
    return active;
  }

  /// Single reason the form currently can't be saved due to category state,
  /// or `null` if it's fine to save - each state gets its own explicit
  /// message rather than a silent default ever being chosen for the admin.
  String? get categorySelectionBlockedReason {
    if (categoriesLoading) return 'Loading categories…';
    if (categoriesUnavailable) {
      return 'Could not load categories. Please try again.';
    }
    if (selectedCategoryMissing) {
      return "This product's category was deleted - please choose a new one.";
    }
    if (_categoryId == null) {
      if (selectableCategories.isEmpty) {
        return 'No active categories available - activate or create one first.';
      }
      return 'Please choose a category.';
    }
    return null;
  }

  bool get canSaveCategorySelection => categorySelectionBlockedReason == null;

  /// AR/VTO-eligibility taxonomy for the currently-resolved category. Only
  /// meaningful once [resolvedCategory] is non-null - callers must gate on
  /// that (or on [canSaveCategorySelection]) rather than trust this default
  /// as if it were a real selection.
  ProductCategory get categoryKind =>
      resolvedCategory?.kind ?? ProductCategory.furniture;

  bool _isActive = true;
  bool get isActive => _isActive;

  ProductPublicationStatus _publicationStatus =
      ProductPublicationStatus.published;
  ProductPublicationStatus get publicationStatus => _publicationStatus;

  bool _showInCatalog = true;

  // Details State
  Set<ProductColorOption> _availableColors = {};
  Set<ProductColorOption> get availableColors => _availableColors;

  Set<ProductSize> _availableSizes = {};
  Set<ProductSize> get availableSizes => _availableSizes;

  // Specifications mapped from common fields
  String _materialOrFabric = '';
  String get materialOrFabric => _materialOrFabric;

  String _dimensions = '';
  String get dimensions => _dimensions;

  String _fitInfo = '';
  String get fitInfo => _fitInfo;

  String _careInstructions = '';
  String get careInstructions => _careInstructions;

  String _sizeGuide = '';
  String get sizeGuide => _sizeGuide;

  // Images State
  List<ProductImageRef> _images = [];
  List<ProductImageRef> get images => List.unmodifiable(_images);

  ProductImageRef? _primaryImage;
  ProductImageRef? get primaryImage => _primaryImage;

  // AR Type State
  ProductExperienceType _experienceType = ProductExperienceType.none;
  ProductExperienceType get experienceType => _experienceType;

  ProductVtoModelType? _vtoModelType;
  ProductVtoModelType? get vtoModelType => _vtoModelType;

  /// Legacy pre-R16 Admin AR & Media staging field. The form no longer
  /// *produces* a value here — it only carries an existing one through on an
  /// edit so an unrelated save never erases pre-9.2 data. The production
  /// Room-AR pointer is [_arMetadata].
  String? _arModelAssetPath;
  String? get arModelAssetPath => _arModelAssetPath;

  double? _arScale;
  double? get arScale => _arScale;

  /// Phase 9.2 R16 — the production Room-AR contract staged by the AR & Media
  /// screen (product-scoped mode). When [_pendingArModelFilePath] is also set,
  /// this is a *placeholder* whose GLB is uploaded and whose `storagePath` /
  /// `sha256` are finalised in [_persist] once the real product id exists.
  ProductArMetadata? _arMetadata;
  ProductArMetadata? get arMetadata => _arMetadata;

  bool _arModelDisabled = false;
  bool get arModelDisabled => _arModelDisabled;

  /// Absolute path of a validated local `.glb` waiting to be uploaded on Save.
  String? _pendingArModelFilePath;
  String? get pendingArModelFilePath => _pendingArModelFilePath;

  /// Storage object path uploaded during the current save, for rollback if the
  /// following Firestore write fails.
  String? _uploadedArModelPathThisSave;

  /// Set when a save / product-delete's Firestore write **succeeded** but the
  /// best-effort cleanup of the superseded / removed Room-AR model object
  /// failed (`deleteArModelByPath` returned `false`). The admin is warned; the
  /// (correct) Firestore write is never undone. Cleared at the start of every
  /// save and of [deleteProduct]. Rollback of a *failed* save is unaffected —
  /// that path already surfaces its own error.
  String? _arModelCleanupWarning;
  String? get arModelCleanupWarning => _arModelCleanupWarning;

  String? _vtoGarmentAssetPath;
  String? get vtoGarmentAssetPath => _vtoGarmentAssetPath;

  bool get isCurrentArConfigured => switch (_experienceType) {
    ProductExperienceType.roomAr =>
      _arMetadata != null || _pendingArModelFilePath != null,
    ProductExperienceType.virtualTryOn => _vtoGarmentAssetPath != null,
    ProductExperienceType.none => false,
  };

  // Section Expansion State
  bool _basicInfoExpanded = true;
  bool get basicInfoExpanded => _basicInfoExpanded;

  bool _pricingExpanded = true;
  bool get pricingExpanded => _pricingExpanded;

  bool _productDetailsExpanded = true;
  bool get productDetailsExpanded => _productDetailsExpanded;

  bool _productImagesExpanded = true;
  bool get productImagesExpanded => _productImagesExpanded;

  bool _arTypeExpanded = true;
  bool get arTypeExpanded => _arTypeExpanded;

  bool _hasUnsavedChanges = false;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  bool _isLoading = false;
  bool get isLoading => _isLoading;

  /// True only while device (`.file`-sourced) images are actively being
  /// uploaded to Storage as part of a save - distinct from [isLoading] (set
  /// for the whole save operation) so the UI can show upload-specific
  /// progress text if desired. Never true when a save has no pending
  /// uploads (e.g. editing text fields only, or re-publishing a draft whose
  /// images already converted to `.network` on an earlier save).
  bool _isUploadingImages = false;
  bool get isUploadingImages => _isUploadingImages;

  String? _error;
  String? get error => _error;

  void _init() {
    if (isEditMode) {
      try {
        _originalProduct = database.getProductById(initialProductId!);
        _populateFormFromProduct(_originalProduct!);
      } catch (e) {
        _error = 'Product not found.';
      }
    } else {
      // Add mode defaults - deliberately no default category (see
      // categorySelectionBlockedReason): the admin must explicitly pick one.
      _isActive = true;
      _publicationStatus = ProductPublicationStatus.published;
      _experienceType = ProductExperienceType.none;
    }

    _addListeners();
  }

  void _addListeners() {
    titleController.addListener(_markDirty);
    subcategoryController.addListener(_markDirty);
    descriptionController.addListener(_markDirty);
    priceController.addListener(_markDirty);
    discountPriceController.addListener(_markDirty);
    stockController.addListener(_markDirty);
  }

  void _markDirty() {
    if (!_hasUnsavedChanges) {
      _hasUnsavedChanges = true;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    categoryRepository.removeListener(_onCategoryRepositoryChanged);
    titleController.dispose();
    subcategoryController.dispose();
    descriptionController.dispose();
    priceController.dispose();
    discountPriceController.dispose();
    stockController.dispose();
    super.dispose();
  }

  void _populateFormFromProduct(ProductModel product) {
    titleController.text = product.title;
    subcategoryController.text = product.subcategory;
    descriptionController.text = product.description;

    if (product.originalPriceAmount != null) {
      discountPriceController.text =
          (product.originalPriceAmount! - product.priceAmount).toString();
      priceController.text = product.originalPriceAmount.toString();
    } else {
      priceController.text = product.priceAmount.toString();
      discountPriceController.clear();
    }

    stockController.text = product.stockQuantity.toString();

    _categoryId = product.categoryId;
    _isActive = product.isActive;
    _publicationStatus = product.publicationStatus;
    _showInCatalog = product.showInCatalog;

    _availableColors = Set.from(product.availableColors);
    _availableSizes = Set.from(product.availableSizes);

    _images = List.from(product.galleryMedia);
    _primaryImage = product.mainImage;
    if (_images.isEmpty && _primaryImage != null) {
      _images.add(_primaryImage!);
    } else if (_images.isNotEmpty && _primaryImage == null) {
      _primaryImage = _images.first;
    } else if (_images.isNotEmpty && _primaryImage != null) {
      if (!_images.any((img) => img.path == _primaryImage!.path)) {
        _images.insert(0, _primaryImage!);
      }
    }

    _experienceType = product.experienceType;
    _vtoModelType = product.vtoModelType;
    _arModelAssetPath = product.arModelAssetPath;
    _arScale = product.arScale;
    _arMetadata = product.arMetadata;
    _arModelDisabled = product.arModelDisabled;
    _pendingArModelFilePath = null;
    _vtoGarmentAssetPath = product.vtoGarmentAssetPath;

    // Parse specifications
    for (var spec in product.specifications) {
      final label = spec.label.toLowerCase();
      if (label == 'material' || label == 'fabric') {
        _materialOrFabric = spec.value;
      } else if (label == 'dimensions') {
        _dimensions = spec.value;
      } else if (label == 'fit') {
        _fitInfo = spec.value;
      } else if (label == 'care' || label == 'care instructions') {
        _careInstructions = spec.value;
      } else if (label == 'size guide') {
        _sizeGuide = spec.value;
      }
    }
  }

  // Setters for UI
  void setCategory(CommerceCategoryModel category) {
    if (_categoryId == category.categoryId) return;
    _categoryId = category.categoryId;
    final kind = category.kind;

    // Validation for AR Type compatibility
    if (kind == ProductCategory.clothing &&
        _experienceType == ProductExperienceType.roomAr) {
      _clearConfigurationFor(_experienceType);
      _experienceType = ProductExperienceType.none;
    } else if (kind != ProductCategory.clothing &&
        _experienceType == ProductExperienceType.virtualTryOn) {
      _clearConfigurationFor(_experienceType);
      _experienceType = ProductExperienceType.none;
    }

    _markDirty();
    notifyListeners();
  }

  Future<bool> requestCategoryChange(
    BuildContext context,
    CommerceCategoryModel category,
  ) async {
    if (_categoryId == category.categoryId) return true;
    final kind = category.kind;
    final disablesCurrentAr =
        (kind == ProductCategory.clothing &&
            _experienceType == ProductExperienceType.roomAr) ||
        (kind != ProductCategory.clothing &&
            _experienceType == ProductExperienceType.virtualTryOn);
    if (disablesCurrentAr && isCurrentArConfigured) {
      final shouldClear = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.largeBorder,
            side: const BorderSide(color: AppColors.primary),
          ),
          title: const Text('Change Category?'),
          content: const Text(
            'This category does not support the current AR type. Its media configuration will be cleared.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep Current'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear & Change'),
            ),
          ],
        ),
      );
      if (shouldClear != true) return false;
    }
    setCategory(category);
    return true;
  }

  void setIsActive(bool active) {
    _isActive = active;
    _markDirty();
    notifyListeners();
  }

  // Details Updates
  void updateMaterialOrFabric(String value) {
    _materialOrFabric = value;
    _markDirty();
  }

  void updateDimensions(String value) {
    _dimensions = value;
    _markDirty();
  }

  void updateFitInfo(String value) {
    _fitInfo = value;
    _markDirty();
  }

  void updateCareInstructions(String value) {
    _careInstructions = value;
    _markDirty();
  }

  void updateSizeGuide(String value) {
    _sizeGuide = value;
    _markDirty();
  }

  void toggleColor(ProductColorOption color) {
    if (_availableColors.contains(color)) {
      _availableColors.remove(color);
    } else {
      _availableColors.add(color);
    }
    _markDirty();
    notifyListeners();
  }

  void toggleSize(ProductSize size) {
    if (_availableSizes.contains(size)) {
      _availableSizes.remove(size);
    } else {
      _availableSizes.add(size);
    }
    _markDirty();
    notifyListeners();
  }

  // Image Management
  void addImages(List<ProductImageRef> newImages, BuildContext context) {
    final availableSlots = 5 - _images.length;
    if (availableSlots <= 0) {
      AppToast.error(context, 'You can add up to 5 product images.');
      return;
    }

    final imagesToAdd = newImages.take(availableSlots).toList();

    _images.addAll(imagesToAdd);

    if (_primaryImage == null && _images.isNotEmpty) {
      _primaryImage = _images.first;
    }

    _markDirty();
    notifyListeners();
  }

  void removeImage(ProductImageRef image) {
    _images.remove(image);
    if (_primaryImage?.path == image.path) {
      _primaryImage = _images.isNotEmpty ? _images.first : null;
    }
    _markDirty();
    notifyListeners();
  }

  void setPrimaryImage(ProductImageRef image) {
    _primaryImage = image;
    _markDirty();
    notifyListeners();
  }

  void moveImageUp(ProductImageRef image) {
    final index = _images.indexOf(image);
    if (index > 0) {
      final temp = _images[index - 1];
      _images[index - 1] = image;
      _images[index] = temp;
      _markDirty();
      notifyListeners();
    }
  }

  void moveImageDown(ProductImageRef image) {
    final index = _images.indexOf(image);
    if (index != -1 && index < _images.length - 1) {
      final temp = _images[index + 1];
      _images[index + 1] = image;
      _images[index] = temp;
      _markDirty();
      notifyListeners();
    }
  }

  void reorderImages(int oldIndex, int newIndex) {
    if (oldIndex < newIndex) {
      newIndex -= 1;
    }
    final item = _images.removeAt(oldIndex);
    _images.insert(newIndex, item);
    _markDirty();
    notifyListeners();
  }

  // AR Type
  void setExperienceType(ProductExperienceType type) {
    if (_experienceType == type) return;
    _clearConfigurationFor(_experienceType);
    _experienceType = type;
    if (type != ProductExperienceType.virtualTryOn) {
      _vtoModelType = null;
    }
    _markDirty();
    notifyListeners();
  }

  Future<bool> requestExperienceTypeChange(
    BuildContext context,
    ProductExperienceType type,
  ) async {
    if (_experienceType == type) return true;
    if (isCurrentArConfigured) {
      final shouldClear = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: AppRadii.largeBorder,
            side: const BorderSide(color: AppColors.primary),
          ),
          title: const Text('Change AR Type?'),
          content: const Text(
            'The current AR media configuration will be cleared.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Keep Current'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Clear & Change'),
            ),
          ],
        ),
      );
      if (shouldClear != true) return false;
    }
    setExperienceType(type);
    return true;
  }

  void _clearConfigurationFor(ProductExperienceType type) {
    if (type == ProductExperienceType.roomAr) {
      _arModelAssetPath = null;
      _arScale = null;
      _arMetadata = null;
      _arModelDisabled = false;
      _pendingArModelFilePath = null;
    } else if (type == ProductExperienceType.virtualTryOn) {
      _vtoGarmentAssetPath = null;
      _vtoModelType = null;
    }
  }

  void setVtoModelType(ProductVtoModelType? type) {
    _vtoModelType = type;
    _markDirty();
    notifyListeners();
  }

  ProductModel buildArConfigurationPreview() {
    return _buildModelForSave(_publicationStatus, configurationPreview: true);
  }

  void applyArMediaConfiguration(ProductModel configuredProduct) {
    if (configuredProduct.experienceType != _experienceType) return;
    if (_experienceType == ProductExperienceType.roomAr) {
      // Phase 9.2 R16: the AR & Media screen returns a production
      // `arMetadata` contract (+ `arModelDisabled`). A staged-but-not-yet-
      // uploaded GLB rides along as `arModelAssetPath` = its local file path;
      // `_persist` uploads it and finalises the contract once the real
      // product id exists.
      _arMetadata = configuredProduct.arMetadata;
      _arModelDisabled = configuredProduct.arModelDisabled;
      _arScale = configuredProduct.arScale;
      final maybePath = configuredProduct.arModelAssetPath;
      _pendingArModelFilePath =
          (_arMetadata != null && _looksLikeLocalFilePath(maybePath))
          ? maybePath
          : null;
    } else if (_experienceType == ProductExperienceType.virtualTryOn) {
      _vtoGarmentAssetPath = configuredProduct.vtoGarmentAssetPath;
      _vtoModelType = configuredProduct.vtoModelType;
    }
    _markDirty();
    notifyListeners();
  }

  /// A pending-upload local `.glb` path — never a Storage object path
  /// (`products/…`) or a URL.
  static bool _looksLikeLocalFilePath(String? path) {
    if (path == null || path.isEmpty) return false;
    if (path.startsWith('products/')) return false;
    if (path.startsWith('http://') || path.startsWith('https://')) return false;
    return path.toLowerCase().endsWith('.glb');
  }

  // Sections
  void toggleBasicInfo() {
    _basicInfoExpanded = !_basicInfoExpanded;
    notifyListeners();
  }

  void togglePricing() {
    _pricingExpanded = !_pricingExpanded;
    notifyListeners();
  }

  void toggleProductDetails() {
    _productDetailsExpanded = !_productDetailsExpanded;
    notifyListeners();
  }

  void toggleProductImages() {
    _productImagesExpanded = !_productImagesExpanded;
    notifyListeners();
  }

  void toggleArType() {
    _arTypeExpanded = !_arTypeExpanded;
    notifyListeners();
  }

  // Validation
  bool _validateImages(BuildContext context) {
    if (_images.isEmpty || _primaryImage == null) {
      AppToast.error(context, 'Add at least 1 product image.');
      return false;
    }
    return true;
  }

  bool _validateCoreFields(BuildContext context) {
    if (titleController.text.trim().isEmpty) {
      AppToast.error(context, 'Product Name is required.');
      return false;
    }
    final p = int.tryParse(priceController.text);
    if (p == null || p <= 0) {
      AppToast.error(context, 'Valid Price is required.');
      return false;
    }
    if (discountPriceController.text.isNotEmpty) {
      final dp = int.tryParse(discountPriceController.text);
      if (dp == null || dp <= 0 || dp >= p) {
        AppToast.error(
          context,
          'Discount Price must be valid and less than Price.',
        );
        return false;
      }
    }
    final stock = int.tryParse(stockController.text);
    if (stock == null || stock < 0) {
      AppToast.error(context, 'Valid Stock Quantity is required.');
      return false;
    }
    return true;
  }

  bool _validateFullPublish(BuildContext context) {
    if (!_validateCoreFields(context)) return false;
    if (descriptionController.text.trim().isEmpty) {
      AppToast.error(context, 'Description is required for publish.');
      return false;
    }
    if (!_validateImages(context)) return false;
    if (_experienceType == ProductExperienceType.virtualTryOn &&
        _vtoModelType == null) {
      AppToast.error(context, 'Select a Male or Female VTO model type.');
      return false;
    }
    return true;
  }

  ProductModel _buildModelForSave(
    ProductPublicationStatus pubStatus, {
    bool configurationPreview = false,
  }) {
    final title = titleController.text.trim();
    final description = descriptionController.text.trim();
    final sub = subcategoryController.text.trim();

    int price = 0;
    int? origPrice;

    final parsedP = int.tryParse(priceController.text);
    if (discountPriceController.text.isNotEmpty) {
      final dp = int.tryParse(discountPriceController.text);
      if (dp != null && parsedP != null) {
        price = parsedP - dp;
        if (price < 0) price = 0;
        origPrice = parsedP;
      }
    } else if (parsedP != null) {
      price = parsedP;
    }

    final stock = int.tryParse(stockController.text) ?? 0;

    // By the time this is called, save validation has already blocked the
    // save via categorySelectionBlockedReason if resolvedCategory were
    // null - this fallback is defensive only, never expected to trigger.
    final kind = categoryKind;

    List<ProductSpecification> specs = [];
    if (kind == ProductCategory.clothing) {
      specs.add(
        ProductSpecification(
          label: 'Fabric',
          value: _materialOrFabric.isNotEmpty ? _materialOrFabric : 'N/A',
        ),
      );
      specs.add(
        ProductSpecification(
          label: 'Fit',
          value: _fitInfo.isNotEmpty ? _fitInfo : 'N/A',
        ),
      );
      specs.add(
        ProductSpecification(
          label: 'Care',
          value: _careInstructions.isNotEmpty ? _careInstructions : 'N/A',
        ),
      );
      specs.add(
        ProductSpecification(
          label: 'Size Guide',
          value: _sizeGuide.isNotEmpty ? _sizeGuide : 'N/A',
        ),
      );
    } else {
      specs.add(
        ProductSpecification(
          label: 'Material',
          value: _materialOrFabric.isNotEmpty ? _materialOrFabric : 'N/A',
        ),
      );
      specs.add(
        ProductSpecification(
          label: 'Dimensions',
          value: _dimensions.isNotEmpty ? _dimensions : 'N/A',
        ),
      );
    }

    final String idToUse = isEditMode
        ? _originalProduct!.id
        : configurationPreview
        ? '__unsaved_product__'
        : title
              .toLowerCase()
              .replaceAll(' ', '-')
              .replaceAll(RegExp(r'[^a-z0-9\-]'), '');

    String skuToUse;
    if (isEditMode) {
      skuToUse = _originalProduct!.sku;
    } else if (configurationPreview) {
      skuToUse = 'Generated when saved';
    } else {
      // A quick fallback mock SKU generator, in reality we'd use the DB's generator if it was exposed
      skuToUse =
          'TWA-${kind.name.substring(0, 3).toUpperCase()}-${DateTime.now().millisecondsSinceEpoch % 10000}';
    }

    return ProductModel(
      id: idToUse,
      sku: skuToUse,
      title: title.isEmpty ? 'Draft Product' : title,
      description: description,
      categoryId: _categoryId ?? '',
      categoryKind: kind,
      subcategory: sub,
      priceAmount: price,
      originalPriceAmount: origPrice,
      stockQuantity: stock,
      // Phase 8.11: preserve the existing server-stamped stock timestamp
      // verbatim on every full-product save (mirrors how addedDate/rating/
      // sku are carried through in edit mode). A product-form save is not a
      // stock-changing inventory operation, so it must never stamp or erase
      // this field - only CommerceDatabase.updateStock owns it. New
      // products start with no timestamp (empty state until the first real
      // inventory update).
      lastStockUpdatedAt: isEditMode
          ? _originalProduct!.lastStockUpdatedAt
          : null,
      isActive: _isActive,
      showInCatalog: _showInCatalog,
      publicationStatus: pubStatus,
      mainImage:
          _primaryImage ?? const ProductImageRef(path: AppAssets.logoMark),
      galleryMedia: _images,
      experienceType: _experienceType,
      vtoModelType: _vtoModelType,
      availableColors: _availableColors,
      defaultColor: _availableColors.isNotEmpty ? _availableColors.first : null,
      availableSizes: _availableSizes,
      defaultSize: _availableSizes.isNotEmpty ? _availableSizes.first : null,
      specifications: specs,
      deliveryEstimate: isEditMode
          ? _originalProduct!.deliveryEstimate
          : '3 - 5 Days',
      addedDate: isEditMode
          ? _originalProduct!.addedDate
          : configurationPreview
          ? DateTime.fromMillisecondsSinceEpoch(0)
          : DateTime.now(),
      rating: isEditMode ? _originalProduct!.rating : 0.0,
      reviewCount: isEditMode ? _originalProduct!.reviewCount : 0,
      popularityScore: isEditMode ? _originalProduct!.popularityScore : 0,
      recommendationRank: isEditMode ? _originalProduct!.recommendationRank : 0,
      // Legacy field: carried through verbatim on an edit (never re-created),
      // cleared when the product is not Room AR.
      arModelAssetPath: _experienceType == ProductExperienceType.roomAr
          ? _arModelAssetPath
          : null,
      arScale: _experienceType == ProductExperienceType.roomAr
          ? _arScale
          : null,
      // Phase 9.2 R16 — the production Room-AR contract + entry-point switch.
      arMetadata: _experienceType == ProductExperienceType.roomAr
          ? _arMetadata
          : null,
      arModelDisabled:
          _experienceType == ProductExperienceType.roomAr && _arModelDisabled,
      vtoGarmentAssetPath: _experienceType == ProductExperienceType.virtualTryOn
          ? _vtoGarmentAssetPath
          : null,
    );
  }

  bool _validateCategorySelection(BuildContext context) {
    final reason = categorySelectionBlockedReason;
    if (reason != null) {
      AppToast.error(context, reason);
      return false;
    }
    return true;
  }

  Future<bool> saveDraft(BuildContext context) async {
    if (!_validateCategorySelection(context)) return false;
    if (!_validateCoreFields(context)) return false;
    if (!_validateImages(context)) return false;
    return _persist(
      context,
      () => _buildModelForSave(ProductPublicationStatus.draft),
      'Draft saved',
    );
  }

  Future<bool> publish(BuildContext context) async {
    if (!_validateCategorySelection(context)) return false;
    if (!_validateFullPublish(context)) return false;
    return _persist(
      context,
      () => _buildModelForSave(ProductPublicationStatus.published),
      'Product published',
    );
  }

  Future<bool> updateProduct(BuildContext context) async {
    if (!_validateCategorySelection(context)) return false;
    if (!_validateFullPublish(context)) return false;
    // Preserve current publication status on normal update
    return _persist(
      context,
      () => _buildModelForSave(_originalProduct!.publicationStatus),
      'Product updated',
    );
  }

  /// Shared save path for [saveDraft]/[publish]/[updateProduct]: uploads any
  /// staged device (`.file`) images to Storage, writes the resulting model
  /// to [database], and rolls back (deletes) only the images uploaded
  /// during THIS save if the Firestore write fails - never touching
  /// previously committed `.network` images (see
  /// `_uploadPendingImages`'s doc comment).
  ///
  /// Staged `_images`/`_primaryImage` are deliberately only overwritten with
  /// the new `.network` refs AFTER `database.addProduct`/`updateProduct`
  /// has actually succeeded - never right after the Storage upload. If the
  /// Firestore write then fails and the just-uploaded objects are rolled
  /// back (deleted), the ViewModel's own staged state must still show the
  /// original `.file` refs, not `.network` refs pointing at objects that no
  /// longer exist - otherwise the form would silently render broken images
  /// after a failed save.
  Future<bool> _persist(
    BuildContext context,
    ProductModel Function() buildModel,
    String successMessage,
  ) async {
    _isLoading = true;
    notifyListeners();

    final uploadedUrlsThisSave = <String>[];
    _uploadedArModelPathThisSave = null;
    _arModelCleanupWarning = null;
    // The committed AR-model object this save may supersede or remove (edit
    // mode only) — captured before the write so we can clean it up after.
    final priorArModelStoragePath = isEditMode
        ? _originalProduct?.arMetadata?.storagePath
        : null;
    try {
      final model = buildModel();
      final uploaded = await _uploadPendingImages(
        model.id,
        uploadedUrlsThisSave,
      );

      // Phase 9.2 R16 — a validated GLB staged in the AR & Media screen is
      // uploaded here, once the real product id exists, and re-verified
      // end-to-end (structure + bounding box + SHA-256) before its contract
      // is trusted. Any failure aborts the save with nothing written.
      final uploadedArMetadata = await _uploadPendingArModel(model.id);

      var finalModel = uploaded == null
          ? model
          : model.copyWith(
              mainImage: uploaded.mainImage,
              galleryMedia: uploaded.gallery,
            );
      if (uploadedArMetadata != null) {
        finalModel = finalModel.copyWith(
          arMetadata: uploadedArMetadata,
          arModelDisabled: false,
        );
      }

      if (isEditMode) {
        await database.updateProduct(finalModel);
      } else {
        await database.addProduct(finalModel);
      }

      // Only now, with the Firestore write confirmed successful, reflect
      // the uploaded images back into local staged state - see this
      // method's doc comment for why the ordering matters.
      if (uploaded != null) {
        _images = uploaded.gallery;
        _primaryImage = uploaded.mainImage;
      }
      if (uploadedArMetadata != null) {
        _arMetadata = uploadedArMetadata;
        _pendingArModelFilePath = null;
      }

      // Phase 9.2 R16 — the AR model was replaced (new versioned object) or
      // removed via the AR & Media flow: best-effort delete the superseded
      // object so a replace/delete through the product form never orphans a
      // GLB in Storage (mirrors the AR & Media screen's own cleanup). The
      // Firestore write has already succeeded and points at the right (new or
      // absent) model — a cleanup failure is NOT rolled back, but it is
      // surfaced honestly instead of a bare "saved".
      final newArModelStoragePath = finalModel.arMetadata?.storagePath;
      if (priorArModelStoragePath != null &&
          priorArModelStoragePath != newArModelStoragePath) {
        final removed = await storageService.deleteArModelByPath(
          priorArModelStoragePath,
        );
        if (!removed) {
          _arModelCleanupWarning =
              'the previous 3D model file could not be removed from storage '
              'and may need manual cleanup in the Firebase console';
        }
      }

      _hasUnsavedChanges = false;
      if (context.mounted) {
        final warning = _arModelCleanupWarning;
        if (warning != null) {
          AppToast.warning(context, '$successMessage — $warning.');
        } else {
          AppToast.success(context, successMessage);
        }
      }
      return true;
    } catch (e) {
      await _rollbackUploadedImages(uploadedUrlsThisSave);
      await _rollbackUploadedArModel();
      if (context.mounted) AppToast.error(context, _writeErrorMessage(e));
      return false;
    } finally {
      _isLoading = false;
      _isUploadingImages = false;
      _isUploadingArModel = false;
      notifyListeners();
    }
  }

  bool _isUploadingArModel = false;

  /// True while the staged Room-AR GLB is being uploaded as part of a save.
  bool get isUploadingArModel => _isUploadingArModel;

  /// Uploads [_pendingArModelFilePath] to
  /// `products/{productId}/ar/model-v{n}.glb`, re-downloads it and re-checks
  /// structure + bounding box + SHA-256, then returns the finalised
  /// [ProductArMetadata] (real storage path + verified hash). Returns `null`
  /// when nothing is staged. Throws on any validation / upload / verification
  /// failure so [_persist] aborts and rolls back.
  Future<ProductArMetadata?> _uploadPendingArModel(String productId) async {
    final localPath = _pendingArModelFilePath;
    final staged = _arMetadata;
    if (localPath == null || staged == null) return null;

    final expected = GlbExpectedBox(
      widthM: staged.widthM,
      depthM: staged.depthM,
      heightM: staged.heightM,
    );
    // Re-validate the local file from its bytes right before upload.
    final inspection = await inspectArGlbFile(
      File(localPath),
      expected: expected,
    );

    _isUploadingArModel = true;
    notifyListeners();

    final version = int.tryParse(staged.modelVersion.trim());
    final resolvedVersion = version == null || version < 1 ? 1 : version;
    final objectName = 'model-v$resolvedVersion.glb';
    final storagePath = await storageService.uploadArModel(
      productId: productId,
      objectName: objectName,
      file: File(localPath),
      provenance: {
        'twinArArModelSha256': inspection.sha256,
        'twinArArModelVersion': '$resolvedVersion',
        'twinArArWidthM': '${staged.widthM}',
        'twinArArDepthM': '${staged.depthM}',
        'twinArArHeightM': '${staged.heightM}',
        'twinArArScaleContract': ProductArMetadata.currentScaleContract,
      },
    );
    _uploadedArModelPathThisSave = storagePath;

    final bytes = await storageService.downloadArModelBytes(storagePath);
    final match = const GlbInspector().inspect(
      bytes,
      expected: expected,
      maxBytes: kArModelTransportMaxBytes,
    );
    if (!match.ok) {
      throw GlbValidationException(
        match.rejectionReason ?? 'uploaded model failed verification',
      );
    }
    if (sha256.convert(bytes).toString() != inspection.sha256) {
      throw const GlbValidationException(
        'uploaded model checksum did not match',
      );
    }

    return staged.copyWith(storagePath: storagePath, sha256: inspection.sha256);
  }

  Future<void> _rollbackUploadedArModel() async {
    final path = _uploadedArModelPathThisSave;
    if (path == null) return;
    try {
      await storageService.deleteArModelByPath(path);
    } catch (_) {
      // Best-effort only - matches the image rollback contract.
    }
    _uploadedArModelPathThisSave = null;
  }

  /// Uploads every currently-staged `.file`-sourced image (device photos
  /// picked but not yet saved) to `products/{productId}/images/
  /// {uniqueObjectName}`, in the staged order. Images already `.network`
  /// (from a prior successful save) or `.asset` (a curated/bundled image)
  /// pass through completely untouched in the returned gallery - they are
  /// never re-uploaded and never deleted, satisfying the "never delete a
  /// previously committed product-image object" rule (a historical
  /// `OrderItemModel` snapshot may still reference it).
  ///
  /// Returns `null` (nothing to do) if no image is currently staged as
  /// `.file`. Every URL uploaded during this call is appended to
  /// [uploadedUrlsThisSave] so the caller can roll them back - and only
  /// them - if the subsequent Firestore write fails. Does NOT mutate
  /// `_images`/`_primaryImage` itself - see `_persist`'s doc comment for why
  /// that must wait until after the Firestore write succeeds.
  ///
  /// **Preflights the entire staged batch before uploading anything.** If
  /// any staged file is missing, an unsupported type, or over
  /// [productImageMaxUploadBytes], this throws [ImageValidationException]
  /// immediately and zero Storage calls are made - a bad file anywhere in a
  /// multi-image batch must abort the whole save cleanly, not fail partway
  /// through after some images already uploaded (which would need its own
  /// rollback and could still leave an inconsistent staged gallery).
  Future<({List<ProductImageRef> gallery, ProductImageRef mainImage})?>
  _uploadPendingImages(
    String productId,
    List<String> uploadedUrlsThisSave,
  ) async {
    final pendingRefs = _images
        .where((ref) => ref.source == ProductImageSource.file)
        .toList();
    if (pendingRefs.isEmpty) return null;

    for (final ref in pendingRefs) {
      await validateImageFileForUpload(
        File(ref.path),
        maxSizeBytes: productImageMaxUploadBytes,
        label: 'image',
      );
    }

    final currentPrimary = _primaryImage;
    final primaryIndex = currentPrimary == null
        ? -1
        : _images.indexOf(currentPrimary);
    _isUploadingImages = true;
    notifyListeners();

    final uploadedGallery = <ProductImageRef>[];
    for (var i = 0; i < _images.length; i++) {
      final ref = _images[i];
      if (ref.source != ProductImageSource.file) {
        uploadedGallery.add(ref);
        continue;
      }
      final objectName = generateUniqueObjectName(
        extension: extensionFromPath(ref.path),
        index: i,
      );
      final url = await storageService.uploadProductImage(
        productId: productId,
        objectName: objectName,
        file: File(ref.path),
      );
      uploadedUrlsThisSave.add(url);
      uploadedGallery.add(
        ProductImageRef(
          path: url,
          source: ProductImageSource.network,
          altText: ref.altText,
        ),
      );
    }

    final newMainImage =
        (primaryIndex >= 0 && primaryIndex < uploadedGallery.length)
        ? uploadedGallery[primaryIndex]
        : (uploadedGallery.isNotEmpty ? uploadedGallery.first : _primaryImage!);

    return (gallery: uploadedGallery, mainImage: newMainImage);
  }

  /// Best-effort delete of only the Storage objects uploaded during the save
  /// that just failed - a partial-batch upload (e.g. image 3 of 5 fails)
  /// never leaves images 1-2 orphaned in Storage with no Firestore
  /// reference. A rollback failure is swallowed (matches
  /// `StorageService.deleteProductImageByUrl`'s own best-effort contract) -
  /// the user already sees the original save-failure toast either way.
  Future<void> _rollbackUploadedImages(List<String> uploadedUrls) async {
    for (final url in uploadedUrls) {
      try {
        await storageService.deleteProductImageByUrl(url);
      } catch (_) {
        // Best-effort only.
      }
    }
  }

  Future<void> deleteProduct(BuildContext context) async {
    if (!isEditMode || _originalProduct == null) return;
    _arModelCleanupWarning = null;
    try {
      await database.deleteProduct(_originalProduct!.id);
      // Phase 9.2 R16 — the whole product is gone; best-effort remove its
      // Room-AR GLB so deleting a product never orphans a Storage object. The
      // product doc (the only thing that referenced it) is already deleted —
      // a cleanup failure is not undone, but it is reported honestly.
      final arModelPath = _originalProduct!.arMetadata?.storagePath;
      if (arModelPath != null) {
        final removed = await storageService.deleteArModelByPath(arModelPath);
        if (!removed) {
          _arModelCleanupWarning =
              'its 3D model file could not be removed from storage and may '
              'need manual cleanup';
        }
      }
      if (context.mounted) {
        final warning = _arModelCleanupWarning;
        if (warning != null) {
          AppToast.warning(context, 'Product deleted — $warning.');
        } else {
          AppToast.success(context, 'Product deleted');
        }
      }
    } catch (e) {
      if (context.mounted) AppToast.error(context, _writeErrorMessage(e));
    }
  }

  /// Never surfaces raw exception text (matches the project's established
  /// `FirebaseAuthRepository._mapAuthError` convention). A [StateError] from
  /// [CommerceDatabase] carries an intentional, already-clean user-facing
  /// message (e.g. the duplicate-product-name check in
  /// `FirestoreCommerceDatabase.addProduct`); [ImageValidationException]
  /// (a staged file failed preflight - missing/unsupported/oversized) and
  /// [StorageServiceException] (an upload itself failed) both already carry
  /// clean, user-facing text too - anything else (network,
  /// permission-denied, etc.) falls back to a generic message.
  String _writeErrorMessage(Object error) {
    if (error is StateError) return error.message;
    if (error is ImageValidationException) return error.message;
    if (error is GlbValidationException) return error.message;
    if (error is StorageServiceException) return error.message;
    return 'Something went wrong. Please try again.';
  }
}
