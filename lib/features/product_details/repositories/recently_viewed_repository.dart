/// Phase 9.3 "Dynamic Home Content" Stage 2 — per-customer product-view
/// history, stored at `users/{uid}/recentlyViewed/{productId}` (document ID
/// **is** the productId, so dedup + "move to front" are the same single
/// write).
///
/// Stage 2 only **records** views (a non-blocking hook on a successful,
/// eligible Product Details load). Home is NOT wired to this yet — that is
/// Stage 3, which will consume [recentProductIds] and filter it against the
/// live catalogue cache.
abstract class RecentlyViewedRepository {
  /// Records (or refreshes to "now") a view of [productId] for the current
  /// signed-in user. **Fire-and-forget**: never throws to the caller and
  /// never blocks Product Details. A no-op when signed out.
  Future<void> recordView(String productId);

  /// The current user's recently-viewed product IDs, **newest first**,
  /// capped at [limit]. `[]` when signed out or on any read error — a view
  /// history that fails to load must never surface as an error.
  Future<List<String>> recentProductIds({int limit = 12});
}
