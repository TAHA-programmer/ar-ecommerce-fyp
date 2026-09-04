import 'package:flutter/foundation.dart';

import '../models/favorite/favorite_model.dart';

/// Canonical `users/{uid}/favorites` data contract (Phase 8.10), mirroring
/// [AddressRepository]'s shape: synchronous/reactive reads, `Future`-based
/// writes, owner-scoped (uid, not role) subscriptions in the real
/// implementation.
///
/// Deliberately stores only the minimal reference (`productId`/`addedAt` -
/// see [FavoriteModel]) - product data is always resolved live via
/// `ProductDetailsRepository`, exactly as before this phase. A product that
/// is deleted/unpublished/otherwise fails to resolve must never remove the
/// favorite itself (that would silently discard a customer's saved intent
/// over what could be a transient lookup failure) - that resolution-layer
/// isolation is the caller's (`FavoritesViewModel`'s) responsibility, not
/// this repository's; see that class's doc comment.
abstract class FavoritesRepository extends ChangeNotifier {
  bool get isLoading;
  bool get hasError;

  List<FavoriteModel> get favorites;

  Set<String> get favoriteProductIds =>
      favorites.map((f) => f.productId).toSet();

  bool isFavorite(String productId) =>
      favorites.any((f) => f.productId == productId);

  /// Idempotent - favoriting an already-favorited product is a no-op that
  /// still completes successfully (mirrors the document-ID-is-the-productId
  /// dedup at the Firestore layer).
  Future<void> addFavorite(String productId);

  /// Idempotent - removing a non-favorited product is a no-op.
  Future<void> removeFavorite(String productId);

  Future<void> toggleFavorite(String productId) {
    return isFavorite(productId)
        ? removeFavorite(productId)
        : addFavorite(productId);
  }
}
