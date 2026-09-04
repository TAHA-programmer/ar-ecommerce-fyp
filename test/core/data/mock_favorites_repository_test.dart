import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';

void main() {
  group('MockFavoritesRepository', () {
    test('addFavorite then isFavorite/favoriteProductIds reflect it', () async {
      final repo = MockFavoritesRepository();
      await repo.addFavorite('p1');
      expect(repo.isFavorite('p1'), isTrue);
      expect(repo.favoriteProductIds, {'p1'});
    });

    test(
      'addFavorite is idempotent - favoriting twice does not duplicate',
      () async {
        final repo = MockFavoritesRepository();
        await repo.addFavorite('p1');
        await repo.addFavorite('p1');
        expect(repo.favorites.length, 1);
      },
    );

    test('removeFavorite is idempotent - removing a non-favorite is a '
        'no-op', () async {
      final repo = MockFavoritesRepository();
      await expectLater(repo.removeFavorite('never-added'), completes);
      expect(repo.favorites, isEmpty);
    });

    test('toggleFavorite flips state each call', () async {
      final repo = MockFavoritesRepository();
      await repo.toggleFavorite('p1');
      expect(repo.isFavorite('p1'), isTrue);
      await repo.toggleFavorite('p1');
      expect(repo.isFavorite('p1'), isFalse);
    });

    test('failAddFavoriteWith causes addFavorite to throw cleanly', () async {
      final repo = MockFavoritesRepository()
        ..failAddFavoriteWith = StateError('boom');
      await expectLater(repo.addFavorite('p1'), throwsA(isA<StateError>()));
    });
  });
}
