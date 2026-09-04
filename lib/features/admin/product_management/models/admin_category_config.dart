import '../../../../core/models/category/commerce_category_model.dart';
import '../../../../core/models/product/product_category.dart';

/// A [CommerceCategoryModel] paired with its live product count, for
/// rendering in Admin Categories Mode. Thin wrapper only - state itself
/// lives in `CategoryRepository`/`CommerceDatabase`, not here (unlike the
/// pre-Phase-8.8 `AdminCategoryConfig`, which was itself the mutable,
/// session-only store).
class AdminCategoryViewItem {
  final CommerceCategoryModel category;
  final int productCount;

  const AdminCategoryViewItem({
    required this.category,
    required this.productCount,
  });

  String get categoryId => category.categoryId;
  String get displayName => category.name;
  String get imageUrl => category.imageUrl;
  bool get isActive => category.isActive;
  bool get isSeeded => category.isSeeded;
  ProductCategory get kind => category.kind;
}
