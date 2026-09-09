import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/features/home/models/category_model.dart';
import 'package:twin_ar/features/home/models/home_banner_model.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/features/home/repositories/home_repository.dart';
import 'package:twin_ar/features/home/repositories/mock_home_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/home/viewmodels/home_viewmodel.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';

/// A [HomeRepository] whose product rails throw until [healed], to exercise
/// the ViewModel's error / retry / recovery path (issue #1: Home used to set
/// `_hasLoaded = true` even on failure and stay permanently blank).
class _FlakyHomeRepository implements HomeRepository {
  bool healed = false;
  int bestSellerCalls = 0;

  Future<List<ProductSummaryModel>> _rail() async {
    if (!healed) {
      throw Exception('[cloud_firestore/permission-denied] simulated');
    }
    return const [];
  }

  @override
  Future<List<HomeBannerModel>> getBanners() async => const [];
  @override
  Future<List<CategoryModel>> getCategories() async => const [];
  @override
  Future<List<ProductSummaryModel>> getBestSellers() {
    bestSellerCalls++;
    return _rail();
  }

  @override
  Future<List<ProductSummaryModel>> getFeaturedProducts() => _rail();
  @override
  Future<List<ProductSummaryModel>> getNewArrivals() => _rail();
  @override
  Future<List<ProductSummaryModel>> getArEnabledProducts() => _rail();
  @override
  Future<List<ProductSummaryModel>> getVirtualTryOnCollection() => _rail();
  @override
  Future<List<ProductSummaryModel>> getPopularFurniture() => _rail();
  @override
  Future<List<ProductSummaryModel>> getRecentlyViewed() => _rail();
  @override
  Future<void> refresh() async {}
}

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

  group('HomeViewModel error / retry / recovery (issue #1)', () {
    late _FlakyHomeRepository flaky;
    late HomeViewModel vm;

    setUp(() {
      final db = MockCommerceDatabase();
      flaky = _FlakyHomeRepository();
      vm = HomeViewModel(
        flaky,
        MockProductDetailsRepository(db, simulateDelay: false),
        CustomerShoppingState(MockFavoritesRepository(), MockCartRepository()),
        db,
      );
    });

    test('a failed load surfaces an honest error state instead of staying '
        'blank, and does NOT latch as loaded', () async {
      await vm.loadHomeData();

      expect(vm.isLoading, false);
      expect(vm.hasError, true);
      expect(vm.isEmpty, true);
    });

    test('retry after the backend recovers loads the feed and clears the '
        'error', () async {
      await vm.loadHomeData();
      expect(vm.hasError, true);

      flaky.healed = true;
      await vm.retry();

      expect(vm.hasError, false);
      expect(vm.isEmpty, true); // rails return [] here, but no error
      expect(vm.isLoading, false);
    });

    test('concurrent loadHomeData calls collapse into one in-flight attempt '
        '(no duplicate failing fan-out)', () async {
      final f1 = vm.loadHomeData();
      final f2 = vm.loadHomeData();
      final f3 = vm.loadHomeData();
      await Future.wait([f1, f2, f3]);

      expect(flaky.bestSellerCalls, 1);
    });

    test('a repeated failing load never gets past the error state but stays '
        'retryable', () async {
      await vm.loadHomeData();
      await vm.retry();
      await vm.retry();
      expect(vm.hasError, true);

      flaky.healed = true;
      await vm.retry();
      expect(vm.hasError, false);
    });
  });
}
