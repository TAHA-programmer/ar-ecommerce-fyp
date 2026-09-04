import '../../../core/models/product/product_summary_model.dart';
import '../../../core/models/product/product_category.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';

class CatalogProductModel {
  final ProductSummaryModel summary;
  final String categoryId;
  final ProductCategory categoryKind;
  final int priceAmount;
  final Set<ProductSize> sizes;
  final Set<ProductColorOption> colors;
  final int recommendationRank;
  final DateTime addedDate;
  final int popularityScore;

  const CatalogProductModel({
    required this.summary,
    required this.categoryId,
    required this.categoryKind,
    required this.priceAmount,
    this.sizes = const {},
    this.colors = const {},
    this.recommendationRank = 0,
    required this.addedDate,
    this.popularityScore = 0,
  });
}
