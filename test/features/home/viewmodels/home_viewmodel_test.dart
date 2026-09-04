import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/features/home/repositories/mock_home_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/home/viewmodels/home_viewmodel.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';

void main() {
  late HomeViewModel viewModel;
  late MockHomeRepository mockRepository;
  late CustomerShoppingState shoppingState;
  late MockProductDetailsRepository mockProductDetailsRepository;

  setUp(() {
    final db = MockCommerceDatabase();
    mockRepository = MockHomeRepository(db);
    mockProductDetailsRepository = MockProductDetailsRepository(
      db,
      simulateDelay: false,
    );
    shoppingState = CustomerShoppingState(
      MockFavoritesRepository(),
      MockCartRepository(),
    );
    viewModel = HomeViewModel(
      mockRepository,
      mockProductDetailsRepository,
      shoppingState,
      db,
    );
  });

  group('HomeViewModel Tests', () {
    test('initial state is correct', () {
      expect(viewModel.isLoading, true);
      expect(viewModel.cartCount, 0);
      expect(viewModel.banners.isEmpty, true);
    });

    test('loadHomeData populates all collections', () async {
      await viewModel.loadHomeData();

      expect(viewModel.isLoading, false);
      expect(viewModel.banners.isNotEmpty, true);
      expect(viewModel.categories.isNotEmpty, true);
      expect(viewModel.bestSellers.isNotEmpty, true);
      expect(viewModel.featuredProducts.isNotEmpty, true);
      expect(viewModel.newArrivals.isNotEmpty, true);
      expect(viewModel.arEnabledProducts.isNotEmpty, true);
      expect(viewModel.virtualTryOnCollection.isNotEmpty, true);
      expect(viewModel.popularFurniture.isNotEmpty, true);
      expect(viewModel.recentlyViewed.isNotEmpty, true);
    });

    test('toggleFavorite toggles product favorite state', () {
      const productId = 'test_id';
      expect(viewModel.isFavorite(productId), false);

      viewModel.toggleFavorite(productId);
      expect(viewModel.isFavorite(productId), true);

      viewModel.toggleFavorite(productId);
      expect(viewModel.isFavorite(productId), false);
    });

    test('addToCart increments cartCount', () async {
      await viewModel.loadHomeData();
      final product = viewModel.featuredProducts.first;

      await viewModel.addToCart(product.id);

      expect(shoppingState.cartCount, 1);
    });
  });
}
