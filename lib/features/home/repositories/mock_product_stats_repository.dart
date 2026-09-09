import 'product_stats_repository.dart';

/// In-memory [ProductStatsRepository] test double. Mirrors the Firestore
/// contract: ranked highest-first, `value > 0` only, deterministic `id`
/// tie-break, capped at the requested `limit`.
///
/// Set [throwOnRead] to simulate a read that blows up *inside* the
/// repository boundary — the real Firestore impl swallows it to `[]`, so
/// this lets a ViewModel test assert the same resilience without depending
/// on that swallow.
class MockProductStatsRepository implements ProductStatsRepository {
  final Map<String, int> unitsSold;
  final Map<String, int> favoriteCount;
  bool throwOnRead;

  MockProductStatsRepository({
    Map<String, int>? unitsSold,
    Map<String, int>? favoriteCount,
    this.throwOnRead = false,
  }) : unitsSold = unitsSold ?? const {},
       favoriteCount = favoriteCount ?? const {};

  List<ProductStatRank> _rank(Map<String, int> source, int limit) {
    final entries = source.entries.where((e) => e.value > 0).toList()
      ..sort((a, b) {
        final byValue = b.value.compareTo(a.value);
        return byValue != 0 ? byValue : a.key.compareTo(b.key);
      });
    return entries
        .take(limit)
        .map((e) => ProductStatRank(e.key, e.value))
        .toList(growable: false);
  }

  @override
  Future<List<ProductStatRank>> topByUnitsSold({int limit = 24}) async {
    if (throwOnRead) throw StateError('productStats read failed');
    return _rank(unitsSold, limit);
  }

  @override
  Future<List<ProductStatRank>> topByFavoriteCount({int limit = 24}) async {
    if (throwOnRead) throw StateError('productStats read failed');
    return _rank(favoriteCount, limit);
  }
}
