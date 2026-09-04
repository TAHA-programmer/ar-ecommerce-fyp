/// Minimal reference-only record for `users/{uid}/favorites/{productId}`
/// (Phase 8.10). Only the product reference and when it was favorited are
/// stored server-side - the actual product data is resolved live via
/// `ProductDetailsRepository`, exactly as it was before this phase.
class FavoriteModel {
  final String productId;
  final DateTime addedAt;

  const FavoriteModel({required this.productId, required this.addedAt});
}
