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

  /// Raw `experienceType == roomAr` flag - drives the "AR" badge on Home/
  /// Explore product cards ONLY. Deliberately NOT the eligibility gate for
  /// anything a customer can actually launch or that a filter can promise
  /// them - see [arRenderable] for that.
  final bool arEnabled;
  final bool tryOnEnabled;

  /// Mirrors `ProductModel.hasRenderableArModel`: `true` only when the
  /// product genuinely has a fully valid, renderable Room-AR model contract
  /// (not just [arEnabled]'s raw experience-type flag). This is the correct
  /// predicate for anything that PROMISES a working AR experience - e.g.
  /// Explore's "AR Available" filter - as opposed to [arEnabled], which
  /// merely drives the cosmetic "AR" badge and stays on the raw flag by
  /// existing design.
  final bool arRenderable;

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
    this.arRenderable = false,
  });

  /// The full source-aware image reference - the preferred way for a
  /// rendering widget to get a [ProductImageRef] for `ProductImageView`.
  ProductImageRef get image =>
      ProductImageRef(path: imageAssetPath, source: imageSource);
}
