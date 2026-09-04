import 'package:flutter/foundation.dart';

import '../models/favorite/favorite_model.dart';
import 'favorites_repository.dart';

/// In-memory test double for [FavoritesRepository] - not used in production.
/// Mirrors `MockCategoryRepository`/`MockAddressRepository`'s role.
class MockFavoritesRepository extends FavoritesRepository {
  final List<FavoriteModel> _favorites;
  bool _isLoading;
  bool _hasError = false;

  Object? failAddFavoriteWith;
  Object? failRemoveFavoriteWith;

  MockFavoritesRepository({List<FavoriteModel>? initialFavorites})
    : _favorites = List.of(initialFavorites ?? const []),
      _isLoading = false;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasError => _hasError;

  @override
  List<FavoriteModel> get favorites => List.unmodifiable(_favorites);

  void simulateLoading() {
    _isLoading = true;
    notifyListeners();
  }

  void simulateError() {
    _isLoading = false;
    _hasError = true;
    notifyListeners();
  }

  void simulateRecovery(List<FavoriteModel> favorites) {
    _favorites
      ..clear()
      ..addAll(favorites);
    _isLoading = false;
    _hasError = false;
    notifyListeners();
  }

  @override
  Future<void> addFavorite(String productId) async {
    if (failAddFavoriteWith != null) throw failAddFavoriteWith!;
    if (_favorites.any((f) => f.productId == productId)) return;
    _favorites.add(
      FavoriteModel(productId: productId, addedAt: DateTime.now()),
    );
    notifyListeners();
  }

  @override
  Future<void> removeFavorite(String productId) async {
    if (failRemoveFavoriteWith != null) throw failRemoveFavoriteWith!;
    _favorites.removeWhere((f) => f.productId == productId);
    notifyListeners();
  }

  @visibleForTesting
  void debugSetFavorites(List<FavoriteModel> favorites) {
    _favorites
      ..clear()
      ..addAll(favorites);
    notifyListeners();
  }
}
