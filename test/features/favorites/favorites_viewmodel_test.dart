import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/favorites/viewmodels/favorites_viewmodel.dart';

void main() {
  late CustomerShoppingState shoppingState;
  late MockProductDetailsRepository repository;
  late FavoritesViewModel viewModel;

  setUp(() {
    shoppingState = CustomerShoppingState(
      MockFavoritesRepository(),
      MockCartRepository(),
    );
    repository = MockProductDetailsRepository(
      MockCommerceDatabase(),
      simulateDelay: false,
    );
  });

  group('FavoritesViewModel Tests', () {
    test('Initialization with empty favorites', () {
      viewModel = FavoritesViewModel(
        shoppingState: shoppingState,
        repository: repository,
      );

      expect(viewModel.isLoading, false);
      expect(viewModel.favoriteProducts.isEmpty, true);
    });

    test('Loads existing favorites on init', () async {
      shoppingState.toggleFavorite('luna-3-seater-sofa');

      viewModel = FavoritesViewModel(
        shoppingState: shoppingState,
        repository: repository,
      );

      // Initially loading
      expect(viewModel.isLoading, true);

      // Wait for load to complete
      await Future.delayed(const Duration(milliseconds: 700));

      expect(viewModel.isLoading, false);
      expect(viewModel.favoriteProducts.length, 1);
      expect(viewModel.favoriteProducts.first.summary.id, 'luna-3-seater-sofa');
    });

    test('Syncs with shopping state additions', () async {
      viewModel = FavoritesViewModel(
        shoppingState: shoppingState,
        repository: repository,
      );

      expect(viewModel.favoriteProducts.isEmpty, true);

      // Add a favorite
      shoppingState.toggleFavorite('luna-3-seater-sofa');

      // Wait for load to complete
      await Future.delayed(const Duration(milliseconds: 700));

      expect(viewModel.favoriteProducts.length, 1);
      expect(viewModel.favoriteProducts.first.summary.id, 'luna-3-seater-sofa');
    });

    test('Syncs with shopping state removals instantly', () async {
      shoppingState.toggleFavorite('luna-3-seater-sofa');

      viewModel = FavoritesViewModel(
        shoppingState: shoppingState,
        repository: repository,
      );

      await Future.delayed(const Duration(milliseconds: 700));
      expect(viewModel.favoriteProducts.length, 1);

      // Remove favorite
      shoppingState.toggleFavorite('luna-3-seater-sofa');

      // Removal should be instant
      expect(viewModel.favoriteProducts.isEmpty, true);
    });

    test(
      'one unresolvable favorite (deleted/unpublished product) does not '
      'block the other, perfectly resolvable favorites from loading - '
      'Phase 8.10 fix for the old Future.wait-aborts-everything bug',
      () async {
        shoppingState.toggleFavorite('luna-3-seater-sofa'); // resolvable
        shoppingState.toggleFavorite('does-not-exist'); // unresolvable

        viewModel = FavoritesViewModel(
          shoppingState: shoppingState,
          repository: repository,
        );

        await Future.delayed(const Duration(milliseconds: 700));

        expect(viewModel.favoriteProducts.length, 1);
        expect(
          viewModel.favoriteProducts.first.summary.id,
          'luna-3-seater-sofa',
        );
        // The unresolvable favorite must NOT be auto-removed just because its
        // product lookup failed - it could be a transient failure.
        expect(shoppingState.isFavorite('does-not-exist'), isTrue);
      },
    );
  });
}
