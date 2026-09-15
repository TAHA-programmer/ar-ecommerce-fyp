import 'package:cloud_firestore/cloud_firestore.dart';

import '../../reviews/models/product_rating_stats.dart';
import '../../reviews/repositories/review_firestore_mapper.dart';
import 'product_stats_repository.dart';

/// Firestore-backed [ProductStatsRepository]. One-shot ranked reads of the
/// `productStats` collection — a single-field `orderBy` (auto-indexed, no
/// composite; `20_DYNAMIC_HOME_CONTENT_PLAN.md` §6.2).
///
/// There is no live listener: Home re-pulls this on load / pull-to-refresh /
/// return-from-a-pushed-screen, which is frequent enough for a display-only
/// ranking. Any error (collection absent because the Stage 2 rules/Functions
/// are not deployed yet, `permission-denied`, offline) resolves to `[]` so
/// Home falls back to the honest rating ranking silently.
class FirestoreProductStatsRepository implements ProductStatsRepository {
  final FirebaseFirestore _firestore;

  FirestoreProductStatsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  Future<List<ProductStatRank>> _topBy(String field, int limit) async {
    try {
      final snapshot = await _firestore
          .collection('productStats')
          .orderBy(field, descending: true)
          .limit(limit)
          .get();
      return snapshot.docs
          .map((d) {
            final raw = d.data()[field];
            return ProductStatRank(d.id, raw is num ? raw.toInt() : 0);
          })
          // Defence in depth — `orderBy` already drops docs missing the
          // field; this also drops a genuine zero so a cold `productStats`
          // doc (created by a favourite that was then removed) never counts
          // as a "real" ranking signal.
          .where((r) => r.value > 0)
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<List<ProductStatRank>> topByUnitsSold({int limit = 24}) =>
      _topBy('unitsSold', limit);

  @override
  Future<List<ProductStatRank>> topByFavoriteCount({int limit = 24}) =>
      _topBy('favoriteCount', limit);

  @override
  Future<Map<String, ProductRatingStats>> ratingStatsFor(
    List<String> productIds,
  ) async {
    if (productIds.isEmpty) return const {};
    // Parallel doc-by-id reads (mirrors `MyReviewsViewModel
    // ._resolveProductSummaries`'s established "resolve N, isolate a
    // per-item failure" pattern) rather than a `whereIn` query - this reads
    // by the KNOWN document id (the productId IS the `productStats` doc id),
    // so there is no filter/order to express and no composite-index
    // question at all.
    final entries = await Future.wait(
      productIds.map((id) async {
        try {
          final doc = await _firestore.collection('productStats').doc(id).get();
          final data = doc.data();
          if (data == null) return null;
          return MapEntry(id, productRatingStatsFromFirestore(data));
        } catch (_) {
          return null; // one failed read must never blank the rest
        }
      }),
    );
    return {
      for (final entry in entries)
        if (entry != null) entry.key: entry.value,
    };
  }
}
