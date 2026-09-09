import 'recently_viewed_repository.dart';

/// In-memory [RecentlyViewedRepository] test double. Mirrors the Firestore
/// semantics: dedup by product ID, revisiting moves a product to the front,
/// newest-first ordering, capped at [keepNewest].
class MockRecentlyViewedRepository implements RecentlyViewedRepository {
  MockRecentlyViewedRepository({this.signedIn = true, this.keepNewest = 30});

  bool signedIn;
  final int keepNewest;

  /// Newest first.
  final List<String> _ordered = [];

  /// Every `recordView` call, in order — for test assertions.
  final List<String> recordedViews = [];

  /// Force the next [recordView] / [recentProductIds] to fail (swallowed).
  bool failNext = false;

  /// Make [recentProductIds] *throw* (the Firestore impl swallows its own
  /// read errors to `[]`; a consumer that does its own resolution — e.g.
  /// the Recently Viewed page — needs to prove it handles a throw too).
  bool throwOnRead = false;

  List<String> get history => List.unmodifiable(_ordered);

  @override
  Future<void> recordView(String productId) async {
    recordedViews.add(productId);
    if (!signedIn || productId.isEmpty) return;
    if (failNext) {
      failNext = false;
      return; // swallowed, exactly like the Firestore impl.
    }
    _ordered.remove(productId); // dedup + move-to-front
    _ordered.insert(0, productId);
    if (_ordered.length > keepNewest) {
      _ordered.removeRange(keepNewest, _ordered.length);
    }
  }

  @override
  Future<List<String>> recentProductIds({int limit = 12}) async {
    if (throwOnRead) throw StateError('recentlyViewed read failed');
    if (!signedIn) return const [];
    if (failNext) {
      failNext = false;
      return const [];
    }
    return _ordered.take(limit).toList(growable: false);
  }
}
