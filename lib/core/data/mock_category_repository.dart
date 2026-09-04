import 'package:flutter/foundation.dart';
import '../models/category/commerce_category_model.dart';
import '../models/product/product_category.dart';
import 'category_repository.dart';
import 'firestore_category_repository.dart'
    show slugifyCategoryName, validateCategoryCreateInput;

/// The five canonical seeded categories, matching
/// `lib/core/data/category_seed_data.dart`'s Dart source of truth. Used as
/// [MockCategoryRepository]'s default starting state so widget/unit tests
/// see the same "Furniture"/"Clothing"/... categories the real app does on
/// a fresh install, with no async gap (construction is fully synchronous -
/// there is no real network/emulator round-trip to await, mirroring
/// `MockCommerceDatabase`'s synchronous-under-the-hood contract).
List<CommerceCategoryModel> defaultMockCategories() => const [
  CommerceCategoryModel(
    categoryId: 'furniture',
    name: 'Furniture',
    key: 'furniture',
    kind: ProductCategory.furniture,
    imageUrl: '',
    isActive: true,
    sortOrder: 10,
  ),
  CommerceCategoryModel(
    categoryId: 'clothing',
    name: 'Clothing',
    key: 'clothing',
    kind: ProductCategory.clothing,
    imageUrl: '',
    isActive: true,
    sortOrder: 20,
  ),
  CommerceCategoryModel(
    categoryId: 'rugs',
    name: 'Rugs',
    key: 'rugs',
    kind: ProductCategory.rugs,
    imageUrl: '',
    isActive: true,
    sortOrder: 30,
  ),
  CommerceCategoryModel(
    categoryId: 'decor',
    name: 'Decor',
    key: 'decor',
    kind: ProductCategory.decor,
    imageUrl: '',
    isActive: true,
    sortOrder: 40,
  ),
  CommerceCategoryModel(
    categoryId: 'lighting',
    name: 'Lighting',
    key: 'lighting',
    kind: ProductCategory.lighting,
    imageUrl: '',
    isActive: true,
    sortOrder: 50,
  ),
];

/// In-memory test double for [CategoryRepository], mirroring
/// `MockCommerceDatabase`/`MockStorageService`'s role in this codebase. Not
/// used in production.
class MockCategoryRepository extends CategoryRepository {
  final List<CommerceCategoryModel> _categories;
  bool _isLoading;
  bool _hasError = false;

  /// When set, the next `addCategory`/`updateCategory`/`deleteCategory` call
  /// throws this instead of succeeding - mirrors `MockStorageService`'s
  /// established failure-injection convention for testing error paths.
  Object? failAddCategoryWith;
  Object? failUpdateCategoryWith;
  Object? failDeleteCategoryWith;

  MockCategoryRepository({List<CommerceCategoryModel>? initialCategories})
    : _categories = List.of(initialCategories ?? defaultMockCategories()),
      _isLoading = false;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasError => _hasError;

  @override
  List<CommerceCategoryModel> get categories {
    final sorted = List<CommerceCategoryModel>.from(_categories);
    sorted.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List.unmodifiable(sorted);
  }

  /// Test-only: simulates the initial-loading state (before the first
  /// snapshot/synchronous load completes).
  void simulateLoading() {
    _isLoading = true;
    notifyListeners();
  }

  /// Test-only: simulates a stream error (e.g. offline).
  void simulateError() {
    _isLoading = false;
    _hasError = true;
    notifyListeners();
  }

  /// Test-only: simulates recovery from a prior error/loading state with a
  /// fresh snapshot.
  void simulateRecovery(List<CommerceCategoryModel> categories) {
    _categories
      ..clear()
      ..addAll(categories);
    _isLoading = false;
    _hasError = false;
    notifyListeners();
  }

  @override
  Future<CommerceCategoryModel> addCategory({
    required String name,
    required ProductCategory kind,
    String imageUrl = '',
    bool isActive = true,
  }) async {
    if (failAddCategoryWith != null) {
      throw failAddCategoryWith!;
    }
    final trimmedName = name.trim();
    final key = slugifyCategoryName(trimmedName);
    validateCategoryCreateInput(trimmedName: trimmedName, key: key, kind: kind);
    if (_categories.any((c) => c.categoryId == key)) {
      throw StateError(
        'A category with this name already exists. Please use a different name.',
      );
    }
    final maxSortOrder = _categories.isEmpty
        ? 0
        : _categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b);
    final model = CommerceCategoryModel(
      categoryId: key,
      name: trimmedName,
      key: key,
      kind: kind,
      imageUrl: imageUrl,
      isActive: isActive,
      sortOrder: maxSortOrder + 10,
    );
    _categories.add(model);
    notifyListeners();
    return model;
  }

  @override
  Future<void> updateCategory(CommerceCategoryModel updated) async {
    if (failUpdateCategoryWith != null) {
      throw failUpdateCategoryWith!;
    }
    final index = _categories.indexWhere(
      (c) => c.categoryId == updated.categoryId,
    );
    if (index == -1) {
      throw StateError('Category not found: ${updated.categoryId}');
    }
    _categories[index] = _categories[index].copyWith(
      name: updated.name,
      imageUrl: updated.imageUrl,
      isActive: updated.isActive,
      sortOrder: updated.sortOrder,
    );
    notifyListeners();
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    if (failDeleteCategoryWith != null) {
      throw failDeleteCategoryWith!;
    }
    if (CommerceCategoryModel.seededCategoryIds.contains(categoryId)) {
      throw StateError('This category cannot be deleted.');
    }
    _categories.removeWhere((c) => c.categoryId == categoryId);
    notifyListeners();
  }

  @visibleForTesting
  void debugSetCategories(List<CommerceCategoryModel> categories) {
    _categories
      ..clear()
      ..addAll(categories);
    notifyListeners();
  }
}
