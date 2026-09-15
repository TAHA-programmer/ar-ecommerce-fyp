import '../../reviews/models/product_rating_stats.dart';

/// One row of a `productStats` ordering query: a product id and the numeric
/// value it was ranked by (`unitsSold` for Best Sellers, `favoriteCount` for
/// Popular). Only rows with a genuinely positive value are ever returned.
class ProductStatRank {
  final String productId;
  final int value;

  const ProductStatRank(this.productId, this.value);
}

/// Read-only access to the server-maintained `productStats/{productId}`
/// ordering aggregates (Dynamic Home Content **Stage 2** backend contract —
/// `20_DYNAMIC_HOME_CONTENT_PLAN.md` §5.3).
///
/// `productStats` is written **exclusively** by Cloud Functions (the webhook
/// finalize path, the cancel trigger, the favourite trigger); a client can
/// only read. Stage 3 consumes this from [HomeViewModel] to order Best
/// Sellers (`unitsSold`) and Popular Furniture & Decor (`favoriteCount`),
/// resolving the returned ids against the live catalogue cache.
///
/// **Every method returns `[]` on any failure** — the collection not existing
/// yet (rules/Functions not deployed), a `permission-denied`, an offline
/// read. A ranking that cannot load must fall back to the honest rating
/// ranking; it must never surface an error banner or a retry loop on Home.
abstract class ProductStatsRepository {
  /// Products with the most `unitsSold`, highest first, `value > 0` only.
  Future<List<ProductStatRank>> topByUnitsSold({int limit = 24});

  /// Products with the most `favoriteCount`, highest first, `value > 0` only.
  Future<List<ProductStatRank>> topByFavoriteCount({int limit = 24});

  /// Rating-aggregate stats (Ratings/Reviews v1 Stage 12 - the SAME
  /// `productStats` rating fields `ReviewsRepository.ratingStatsFor` reads
  /// for a single product, here bulk-read for a whole page of Home cards)
  /// for exactly the given [productIds], keyed by id. An id absent from the
  /// result never had a `productStats` doc or has zero published reviews -
  /// callers treat a missing key exactly like [ProductRatingStats.zero],
  /// never an error. Never throws - resolves to `{}` on any failure, the
  /// same silent-fallback contract as [topByUnitsSold]/[topByFavoriteCount].
  Future<Map<String, ProductRatingStats>> ratingStatsFor(
    List<String> productIds,
  );
}
