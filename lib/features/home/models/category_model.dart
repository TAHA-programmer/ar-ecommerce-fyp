import '../../../core/models/product/product_category.dart';

class CategoryModel {
  final String id;
  final String name;

  /// Bundled asset path - used by [MockHomeRepository]'s static curated
  /// tiles. Empty when this tile came from real Firestore data.
  final String imageAssetPath;

  /// Storage download URL - used when this tile came from a real
  /// `categories/{categoryId}` document (Phase 8.8b), rendered via
  /// `Image.network`. Empty when this tile is one of the static mock tiles,
  /// or when a real category hasn't had a photo uploaded yet.
  final String imageUrl;

  /// The category's AR/VTO taxonomy kind - every real category has one of
  /// the five closed values (never `.all`), used by [CategoryTile] to pick
  /// a themed bundled fallback image when [imageUrl]/[imageAssetPath] are
  /// both empty, so a brand-new Admin-created category never shows as a
  /// bare placeholder box before its own photo is uploaded. Defaults to
  /// `furniture` for the static mock tiles, which always set
  /// [imageAssetPath] anyway and never reach the fallback path.
  final ProductCategory kind;

  const CategoryModel({
    required this.id,
    required this.name,
    this.imageAssetPath = '',
    this.imageUrl = '',
    this.kind = ProductCategory.furniture,
  });
}
