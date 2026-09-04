import '../../../core/models/product/product_category.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';

class ExploreFilterState {
  final ProductCategory category;
  final String? categoryId;
  final double minimumPrice;
  final double maximumPrice;
  final bool inStockOnly;
  final bool arAvailable;
  final bool tryOnAvailable;
  final Set<ProductSize> selectedSizes;
  final Set<ProductColorOption> selectedColors;

  const ExploreFilterState({
    this.category = ProductCategory.all,
    this.categoryId,
    this.minimumPrice = 0,
    this.maximumPrice = 50000,
    this.inStockOnly = false,
    this.arAvailable = false,
    this.tryOnAvailable = false,
    this.selectedSizes = const {},
    this.selectedColors = const {},
  });

  // [category] (broad kind) and [categoryId] (exact category) are mutually
  // exclusive - at most one category filter is ever active at a time, per
  // Phase 8.8b's exact-vs-kind filtering split. Passing [category] clears
  // any active [categoryId]; passing [categoryId] resets [category] back to
  // `.all`. [clearCategoryId] clears an exact filter without touching kind
  // (used when the kind chips UI is opened while an exact filter is active).
  ExploreFilterState copyWith({
    ProductCategory? category,
    String? categoryId,
    bool clearCategoryId = false,
    double? minimumPrice,
    double? maximumPrice,
    bool? inStockOnly,
    bool? arAvailable,
    bool? tryOnAvailable,
    Set<ProductSize>? selectedSizes,
    Set<ProductColorOption>? selectedColors,
  }) {
    return ExploreFilterState(
      category: categoryId != null
          ? ProductCategory.all
          : (category ?? this.category),
      categoryId: category != null
          ? null
          : (clearCategoryId ? null : (categoryId ?? this.categoryId)),
      minimumPrice: minimumPrice ?? this.minimumPrice,
      maximumPrice: maximumPrice ?? this.maximumPrice,
      inStockOnly: inStockOnly ?? this.inStockOnly,
      arAvailable: arAvailable ?? this.arAvailable,
      tryOnAvailable: tryOnAvailable ?? this.tryOnAvailable,
      selectedSizes: selectedSizes ?? this.selectedSizes,
      selectedColors: selectedColors ?? this.selectedColors,
    );
  }

  // Define what the default state looks like when "Reset" is pressed.
  factory ExploreFilterState.defaultState() {
    return const ExploreFilterState();
  }

  // Helper to check if any non-category filter is active (useful for UI indicators)
  bool get hasActiveFilters {
    return minimumPrice > 0 ||
        maximumPrice < 50000 ||
        inStockOnly ||
        arAvailable ||
        tryOnAvailable ||
        selectedSizes.isNotEmpty ||
        selectedColors.isNotEmpty;
  }
}
