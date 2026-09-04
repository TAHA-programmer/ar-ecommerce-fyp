import 'product_image_ref.dart';

class ProductSummaryModel {
  final String id;
  final String title;
  final String imageAssetPath;

  /// Carries [mainImage]'s source (`asset`/`file`/`network`) alongside the
  /// plain path in [imageAssetPath], so every widget rendering this summary
  /// can reconstruct a full [ProductImageRef] and render it through
  /// `ProductImageView` instead of assuming `Image.asset` - the Phase 8.7
  /// source-awareness fix. Defaults to `.asset` (the pre-8.7 behavior) so no
  /// call site outside `ProductModelMappers.toSummaryModel()` needs to
  /// change to keep compiling.
  final ProductImageSource imageSource;

  final String currentPrice;
  final String? originalPrice;
  final String? discountPercentage;
  final double rating;
  final int reviewCount;
  final bool inStock;
  final bool arEnabled;
  final bool tryOnEnabled;

  const ProductSummaryModel({
    required this.id,
    required this.title,
    required this.imageAssetPath,
    this.imageSource = ProductImageSource.asset,
    required this.currentPrice,
    this.originalPrice,
    this.discountPercentage,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.inStock = true,
    this.arEnabled = false,
    this.tryOnEnabled = false,
  });

  /// The full source-aware image reference - the preferred way for a
  /// rendering widget to get a [ProductImageRef] for `ProductImageView`.
  ProductImageRef get image =>
      ProductImageRef(path: imageAssetPath, source: imageSource);
}
