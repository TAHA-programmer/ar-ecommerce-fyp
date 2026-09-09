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

  /// `true` when this intent originates from a Home "See all" / hero CTA /
  /// category tile / search. `ExploreViewModel.applyIntent` then FIRST resets
  /// Explore to a neutral state (no search, no advanced filters,
  /// `ProductCategory.all`, `recommended` sort) and ONLY THEN applies this
  /// intent's one preset dimension — so a Home entry never inherits the
  /// Explore tab's persisted / Figma-default filters (In Stock + AR + Beige).
  /// A direct Explore-tab open passes no intent at all and keeps its session
  /// state unchanged.
  final bool fromHome;

  const ExploreLaunchIntent({
    this.searchQuery,
    this.category,
    this.categoryId,
    this.arOnly = false,
    this.tryOnOnly = false,
    this.sortOption,
    this.productIds,
    this.openFilterSheet = false,
    this.fromHome = false,
  });
}
