import 'package:cloud_firestore/cloud_firestore.dart';

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
}
