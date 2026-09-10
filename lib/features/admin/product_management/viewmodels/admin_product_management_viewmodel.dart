import 'package:flutter/material.dart';
import '../../../../core/data/category_repository.dart';
import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/product/product_category.dart';
import '../../../../core/models/product/product_experience_type.dart';
import '../../../../core/models/product/product_image_ref.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/services/firebase_storage_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../models/admin_category_config.dart';
import '../models/admin_category_sort_option.dart';
import '../models/admin_product_filter_state.dart';
import '../models/admin_product_management_mode.dart';
import '../models/admin_product_sort_option.dart';

class AdminProductManagementViewModel extends ChangeNotifier {
  final CommerceDatabase _database;
  final CategoryRepository _categoryRepository;
  final StorageService storageService;

  AdminProductManagementMode _mode = AdminProductManagementMode.products;
  AdminProductManagementMode get mode => _mode;

  // --- Products State ---
  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  AdminProductFilterState _filterState = AdminProductFilterState.defaultState();
  AdminProductFilterState get filterState => _filterState;

  AdminProductSortOption _sortOption = AdminProductSortOption.newest;
  AdminProductSortOption get sortOption => _sortOption;

  // --- Categories State ---
  String _categorySearchQuery = '';
  String get categorySearchQuery => _categorySearchQuery;

  AdminProductStatusFilter _categoryFilterStatus = AdminProductStatusFilter.all;
  AdminProductStatusFilter get categoryFilterStatus => _categoryFilterStatus;

  AdminCategorySortOption _categorySortOption = AdminCategorySortOption.nameAZ;
  AdminCategorySortOption get categorySortOption => _categorySortOption;

  /// `true` while a delete-category write is in flight - guards against a
  /// duplicate submit (e.g. a fast double-tap) firing a second concurrent
  /// delete for the same category. Create/update no longer live on this
  /// ViewModel at all - see `AdminCategoryFormViewModel`.
  bool _isDeletingCategory = false;
  bool get isDeletingCategory => _isDeletingCategory;

  bool get isCategoriesLoading => _categoryRepository.isLoading;
  bool get hasCategoriesError => _categoryRepository.hasError;

  AdminProductManagementViewModel(
    this._database,
    this._categoryRepository, {
    StorageService? storageService,
  }) : storageService = storageService ?? FirebaseStorageService() {
    _database.addListener(_onDatabaseChanged);
    _categoryRepository.addListener(_onCategoryRepositoryChanged);
  }

  void _onDatabaseChanged() {
    notifyListeners();
  }

  void _onCategoryRepositoryChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _database.removeListener(_onDatabaseChanged);
    _categoryRepository.removeListener(_onCategoryRepositoryChanged);
    super.dispose();
  }

  void setMode(AdminProductManagementMode mode) {
    _mode = mode;
    notifyListeners();
  }

  // --- Products Actions ---

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void updateFilter(AdminProductFilterState newState) {
    _filterState = newState;
    notifyListeners();
  }

  void resetFilters() {
    _filterState = AdminProductFilterState.defaultState();
    notifyListeners();
  }

  void setSortOption(AdminProductSortOption option) {
    _sortOption = option;
    notifyListeners();
  }

  /// Set when a product-delete's Firestore write succeeded but the best-effort
  /// cleanup of its Room-AR GLB failed. Cleared at the start of every
  /// [deleteProduct]. Mirrors `AdminProductFormViewModel.arModelCleanupWarning`.
  String? _arModelCleanupWarning;
  String? get arModelCleanupWarning => _arModelCleanupWarning;

  /// Returns `true` on success. On failure, shows a clean [AppToast.error]
  /// (never raw exception text - mirrors `AdminProductFormViewModel`'s
  /// `_writeErrorMessage` convention) and returns `false`, so the caller
  /// (the delete-confirmation dialog) can leave the dialog open instead of
  /// popping as if the delete had succeeded.
  ///
  /// Phase 9.2 R16: also best-effort deletes the product's Room-AR GLB from
  /// Storage — the products-list delete path previously left it orphaned
  /// (only the Edit-Product form's Delete cleaned it up). The Firestore delete
  /// is authoritative; a Storage-cleanup failure is surfaced as an honest
  /// warning (`arModelCleanupWarning` + a toast) and never turns a successful
  /// delete into a failure.
  ///
  /// Also best-effort removes the product's **own product images**
  /// (`products/{id}/images/**`) so deleting a product never leaves an orphaned
  /// `products/{id}/` folder. Only URLs that resolve to *this* product's own
  /// images/ folder are deleted — an image URL that resolves elsewhere (or
  /// isn't a Storage URL) is left untouched. A historical `OrderItemModel`
  /// order snapshot may still hold a copy of a deleted image's URL string; that
  /// line item's thumbnail falls back to `ProductImageView`'s broken-image
  /// placeholder (no crash). The developer accepted that trade-off.
  ///
  /// Returns `true` once the Firestore document is gone (the product IS deleted
  /// from the catalog, so the dialog closes); returns `false` only when the
  /// Firestore delete itself failed. Any Storage-cleanup failure is surfaced as
  /// a **warning** (never a plain "deleted" success) via [arModelCleanupWarning]
  /// + a toast — the delete is not reported as fully clean.
  Future<bool> deleteProduct(BuildContext context, String productId) async {
    _arModelCleanupWarning = null;
    // Snapshot every owned reference BEFORE the doc is gone. Only refs that
    // provably belong to THIS product are captured — a corrupted/foreign VTO
    // path or a cross-product image URL is never passed to Storage.
    String? arModelStoragePath;
    var vtoOwnedPaths = const <String>{};
    var vtoHadForeignPath = false;
    var imageUrls = const <String>{};
    try {
      final product = _database.getProductById(productId);
      arModelStoragePath = product.arMetadata?.storagePath;
      final vto = product.vtoMetadata;
      if (vto != null) {
        vtoOwnedPaths = vto.ownedAssetPaths(productId);
        vtoHadForeignPath = vto.hasForeignAssetPath(productId);
      }
      imageUrls = {
        if (product.mainImage.source == ProductImageSource.network)
          product.mainImage.path,
        for (final img in product.galleryMedia)
          if (img.source == ProductImageSource.network) img.path,
      };
    } catch (_) {
      // Product not in the local cache - nothing to clean up.
    }

    try {
      await _database.deleteProduct(productId);
    } catch (_) {
      if (context.mounted) {
        AppToast.error(context, 'Could not delete product. Please try again.');
      }
      return false;
    }

    var cleanupFailed = false;
    if (arModelStoragePath != null &&
        !await storageService.deleteArModelByPath(arModelStoragePath)) {
      cleanupFailed = true;
    }
    for (final path in vtoOwnedPaths) {
      if (!await storageService.deleteVtoGarmentByPath(path)) cleanupFailed = true;
    }
    for (final url in imageUrls) {
      if (!await storageService.deleteOwnedProductImage(
        productId: productId,
        downloadUrl: url,
      )) {
        cleanupFailed = true;
      }
    }

    if (cleanupFailed || vtoHadForeignPath) {
      _arModelCleanupWarning = [
        'Product deleted —',
        if (cleanupFailed)
          'one or more of its Storage objects could not be removed',
        if (vtoHadForeignPath)
          '${cleanupFailed ? 'and' : ''} one or more stored garment paths did '
              'not belong to this product and were left untouched',
        '— manual cleanup in the Firebase console may be needed.',
      ].join(' ');
      if (context.mounted) AppToast.warning(context, _arModelCleanupWarning!);
    }
    return true;
  }

  List<ProductModel> get filteredProducts {
    var result = _database.products.toList();

    // 1. Search - matches title, SKU, broad kind label, and the product's
    // real assigned category name. The categoryId->name lookup is built
    // once per filter pass, not once per product (Phase 8.8b, review point
    // 5).
    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      final categoryNameById = {
        for (final c in _categoryRepository.categories) c.categoryId: c.name,
      };
      result = result.where((p) {
        final nameMatches = p.title.toLowerCase().contains(query);
        final kindMatches = p.categoryKind.label.toLowerCase().contains(query);
        final categoryName = categoryNameById[p.categoryId] ?? '';
        final categoryNameMatches = categoryName.toLowerCase().contains(query);
        final skuMatches = p.sku.toLowerCase().contains(query);
        return nameMatches || kindMatches || categoryNameMatches || skuMatches;
      }).toList();
    }

    // 2. Filter - Category (broad kind, matches the filter sheet's chips)
    if (_filterState.category != null) {
      result = result
          .where((p) => p.categoryKind == _filterState.category)
          .toList();
    }

    // 3. Filter - Status
    if (_filterState.status != AdminProductStatusFilter.all) {
      final wantActive = _filterState.status == AdminProductStatusFilter.active;
      result = result.where((p) => p.isActive == wantActive).toList();
    }

    // 4. Filter - Stock
    if (_filterState.stock != AdminProductStockFilter.all) {
      result = result.where((p) {
        final qty = p.stockQuantity;
        switch (_filterState.stock) {
          case AdminProductStockFilter.inStock:
            return qty > CommerceDatabase.lowStockThreshold;
          case AdminProductStockFilter.lowStock:
            return qty > 0 && qty <= CommerceDatabase.lowStockThreshold;
          case AdminProductStockFilter.outOfStock:
            return qty == 0;
          default:
            return true;
        }
      }).toList();
    }

    // 5. Filter - AR Type
    if (_filterState.arType != AdminProductArFilter.all) {
      result = result.where((p) {
        switch (_filterState.arType) {
          case AdminProductArFilter.none:
            return p.experienceType == ProductExperienceType.none;
          case AdminProductArFilter.roomAr:
            return p.experienceType == ProductExperienceType.roomAr;
          case AdminProductArFilter.virtualTryOn:
            return p.experienceType == ProductExperienceType.virtualTryOn;
          default:
            return true;
        }
      }).toList();
    }

    // 6. Sort
    switch (_sortOption) {
      case AdminProductSortOption.newest:
        result.sort((a, b) => b.addedDate.compareTo(a.addedDate));
        break;
      case AdminProductSortOption.nameAZ:
        result.sort(
          (a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()),
        );
        break;
      case AdminProductSortOption.nameZA:
        result.sort(
          (a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()),
        );
        break;
      case AdminProductSortOption.priceLowToHigh:
        result.sort((a, b) => a.priceAmount.compareTo(b.priceAmount));
        break;
      case AdminProductSortOption.priceHighToLow:
        result.sort((a, b) => b.priceAmount.compareTo(a.priceAmount));
        break;
      case AdminProductSortOption.stockLowToHigh:
        result.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
        break;
      case AdminProductSortOption.stockHighToLow:
        result.sort((a, b) => b.stockQuantity.compareTo(a.stockQuantity));
        break;
    }

    return result;
  }

  int get totalProductsCount => _database.products.length;

  // --- Categories Actions ---

  void setCategorySearchQuery(String query) {
    _categorySearchQuery = query;
    notifyListeners();
  }

  void setCategoryFilterStatus(AdminProductStatusFilter status) {
    _categoryFilterStatus = status;
    notifyListeners();
  }

  void resetCategoryFilters() {
    _categoryFilterStatus = AdminProductStatusFilter.all;
    notifyListeners();
  }

  void setCategorySortOption(AdminCategorySortOption option) {
    _categorySortOption = option;
    notifyListeners();
  }

  List<AdminCategoryViewItem> get filteredCategories {
    // Phase 8.8b: a real categoryId reference match, not a string-name
    // coincidence. This count is a fast, client-cache-based UI convenience
    // (product-count display, delete-button greying) only - the actual
    // deletion safety boundary is enforced independently and authoritatively
    // by CategoryRepository.deleteCategory's own live Firestore query, so a
    // stale/lagging local cache here can never let a referenced category
    // actually be deleted (see that method's doc comment).
    var result = _categoryRepository.categories.map((category) {
      final productCount = _database.products
          .where((p) => p.categoryId == category.categoryId)
          .length;
      return AdminCategoryViewItem(
        category: category,
        productCount: productCount,
      );
    }).toList();

    // 1. Search
    final query = _categorySearchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result
          .where((c) => c.displayName.toLowerCase().contains(query))
          .toList();
    }

    // 2. Filter Status
    if (_categoryFilterStatus != AdminProductStatusFilter.all) {
      final wantActive =
          _categoryFilterStatus == AdminProductStatusFilter.active;
      result = result.where((c) => c.isActive == wantActive).toList();
    }

    // 3. Sort
    switch (_categorySortOption) {
      case AdminCategorySortOption.nameAZ:
        result.sort(
          (a, b) => a.displayName.toLowerCase().compareTo(
            b.displayName.toLowerCase(),
          ),
        );
        break;
      case AdminCategorySortOption.nameZA:
        result.sort(
          (a, b) => b.displayName.toLowerCase().compareTo(
            a.displayName.toLowerCase(),
          ),
        );
        break;
      case AdminCategorySortOption.mostProducts:
        result.sort((a, b) => b.productCount.compareTo(a.productCount));
        break;
      case AdminCategorySortOption.fewestProducts:
        result.sort((a, b) => a.productCount.compareTo(b.productCount));
        break;
    }

    return result;
  }

  int get totalCategoriesCount => _categoryRepository.categories.length;

  /// Whether [item] is currently eligible for hard deletion. Single source
  /// of truth for this decision - the View reads this (and
  /// [categoryDeletionBlockedReason]) to decide which dialog to show, but
  /// the actual [deleteCategory] call below enforces the same rule
  /// independently, so no other UI call site can bypass it.
  bool canDeleteCategory(AdminCategoryViewItem item) =>
      !item.isSeeded && item.productCount == 0;

  /// User-facing reason [item] cannot currently be deleted, or `null` if it
  /// can be.
  String? categoryDeletionBlockedReason(AdminCategoryViewItem item) {
    if (item.isSeeded) {
      return 'This is a built-in category and cannot be deleted.';
    }
    if (item.productCount > 0) {
      return 'This category cannot be deleted because it contains '
          '${item.productCount} ${item.productCount == 1 ? 'product' : 'products'}.\n\n'
          'Remove or reassign all products first.';
    }
    return null;
  }

  /// Deletes a custom (non-seeded) category with zero products. Re-checks
  /// [canDeleteCategory] independently of the View, so no other call site
  /// can bypass the seeded-protection/zero-product-count rule. The
  /// Firestore document is deleted FIRST; its image (if any) is best-effort
  /// deleted only afterward, so a Storage failure never leaves a dangling
  /// Firestore reference and a Firestore failure never leaves an orphaned
  /// image with no document to show it was ever attached to.
  Future<bool> deleteCategory(
    BuildContext context,
    AdminCategoryViewItem item,
  ) async {
    if (_isDeletingCategory) return false;

    final blockedReason = categoryDeletionBlockedReason(item);
    if (blockedReason != null) {
      if (context.mounted) AppToast.error(context, blockedReason);
      return false;
    }

    _isDeletingCategory = true;
    notifyListeners();
    try {
      final imageUrl = item.imageUrl;
      await _categoryRepository.deleteCategory(item.categoryId);
      if (imageUrl.isNotEmpty) {
        await storageService.deleteCategoryImageByUrl(imageUrl);
      }
      if (context.mounted) {
        AppToast.success(context, 'Category deleted successfully');
      }
      return true;
    } catch (e) {
      if (context.mounted) AppToast.error(context, _categoryErrorMessage(e));
      return false;
    } finally {
      _isDeletingCategory = false;
      notifyListeners();
    }
  }

  /// Never surfaces raw exception text (matches
  /// `AdminProductFormViewModel._writeErrorMessage`'s established
  /// convention). A [StateError] from [CategoryRepository] (e.g. a
  /// seeded-category delete attempt) already carries a clean, user-facing
  /// message - anything else (network, permission-denied, etc.) falls back
  /// to a generic message rather than exposing raw platform/Firebase error
  /// text.
  String _categoryErrorMessage(Object error) {
    if (error is StateError) return error.message;
    return 'Something went wrong. Please try again.';
  }
}
