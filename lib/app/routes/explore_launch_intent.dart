import '../../core/models/product/product_category.dart';
import '../../features/explore/models/explore_sort_option.dart';

class ExploreLaunchIntent {
  final String? searchQuery;
  final ProductCategory? category;
  final String? categoryId;
  final bool arOnly;
  final bool tryOnOnly;
  final ExploreSortOption? sortOption;
  final List<String>? productIds;
  final bool openFilterSheet;

  const ExploreLaunchIntent({
    this.searchQuery,
    this.category,
    this.categoryId,
    this.arOnly = false,
    this.tryOnOnly = false,
    this.sortOption,
    this.productIds,
    this.openFilterSheet = false,
  });
}
