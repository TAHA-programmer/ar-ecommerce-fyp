import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_publication_status.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/features/home/models/category_model.dart';
import 'package:twin_ar/features/home/models/home_banner_model.dart';
import 'package:twin_ar/features/home/repositories/home_repository.dart';
import 'package:twin_ar/features/home/repositories/mock_home_repository.dart';
import 'package:twin_ar/features/home/viewmodels/home_viewmodel.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

const _renderableAr = ProductArMetadata(
  storagePath: 'products/x/ar/model-v1.glb',
  modelVersion: '1',
  sha256: 'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
  widthM: 0.5,
  depthM: 0.5,
  heightM: 0.5,
);

ProductModel _product(
  String id, {
  DateTime? addedDate,
  bool isActive = true,
  ProductPublicationStatus status = ProductPublicationStatus.published,
  ProductExperienceType experience = ProductExperienceType.none,
  ProductArMetadata? arMetadata,
  ProductCategory kind = ProductCategory.decor,
  int recommendationRank = 50,
  double rating = 3.0,
  int reviewCount = 1,
}) => ProductModel(
  id: id,
  sku: 'SKU-$id',
  title: id,
  description: '',
  categoryId: kind.name,
  categoryKind: kind,
  subcategory: 'Sub',
  priceAmount: 1000,
  stockQuantity: 5,
  isActive: isActive,
  publicationStatus: status,
  mainImage: const ProductImageRef(path: 'assets/x.png'),
  experienceType: experience,
  arMetadata: arMetadata,
  addedDate: addedDate ?? DateTime(2026, 1, 1),
  recommendationRank: recommendationRank,
  rating: rating,
  reviewCount: reviewCount,
  deliveryEstimate: '3-5 days',
);

class _CategoriesFailRepository implements HomeRepository {
  bool healed = false;
  int categoriesCalls = 0;

  @override
  Future<List<HomeBannerModel>> getBanners() async => const [
    HomeBannerModel(
      id: 'b1',
      imageAssetPath: 'x',
      title1: 'a',
      title2: 'b',
      title3: 'c',
      body: 'd',
      ctaText: 'e',
    ),
  ];
  @override
  Future<List<CategoryModel>> getCategories() async {
    categoriesCalls++;
    if (!healed) throw Exception('[cloud_firestore/permission-denied]');
    return const [CategoryModel(id: 'c1', name: 'Furniture')];
  }

  @override
  Future<List<ProductSummaryModel>> getBestSellers() async => const [];
  @override
  Future<List<ProductSummaryModel>> getFeaturedProducts() async => const [];
  @override
  Future<List<ProductSummaryModel>> getNewArrivals() async => const [];
  @override
  Future<List<ProductSummaryModel>> getArEnabledProducts() async => const [];
  @override
  Future<List<ProductSummaryModel>> getVirtualTryOnCollection() async =>
      const [];
  @override
  Future<List<ProductSummaryModel>> getPopularFurniture() async => const [];
  @override
  Future<List<ProductSummaryModel>> getRecentlyViewed() async => const [];
  @override
  Future<void> refresh() async {}
}

class _EmptyCommerceDatabase extends CommerceDatabase {
  final List<ProductModel> _products = [];
  @override
  List<ProductModel> get products => List.unmodifiable(_products);
  @override
  List<OrderModel> get orders => const [];
  @override
  List<PaymentRecord> get payments => const [];
  @override
  ProductModel getProductById(String id) => throw StateError('empty');
  @override
  Future<void> addProduct(ProductModel product) async {
    _products.add(product);
    notifyListeners();
  }

  @override
  Future<void> updateProduct(ProductModel product) async {}
  @override
  Future<void> setProductActive(String productId, bool isActive) async {}
  @override
  Future<void> updateStock(String productId, int newStockQuantity) async {}
  @override
  Future<void> deleteProduct(String productId) async {}
  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {}
}

CustomerShoppingState _shopping() =>
    CustomerShoppingState(MockFavoritesRepository(), MockCartRepository());

void main() {
  group('HomeViewModel — dynamic sections (Stage 1)', () {
    late MockCommerceDatabase db;
    late HomeViewModel vm;

    setUp(() {
      db = MockCommerceDatabase();
      vm = HomeViewModel(
        MockHomeRepository(db),
        MockProductDetailsRepository(db, simulateDelay: false),
        _shopping(),
        db,
      );
    });

    test('initial state: loading', () {
      expect(vm.isLoading, true);
      expect(vm.cartCount, 0);
    });

    test('loadHomeData populates every section from real data (no hardcoded '
        'IDs, no fabricated commerce claims)', () async {
      await vm.loadHomeData();

      expect(vm.isLoading, false);
      expect(vm.banners, isNotEmpty);
      expect(vm.categories, isNotEmpty);
      expect(vm.newArrivalsStatus, HomeSectionStatus.ready);
      expect(vm.arEnabledStatus, HomeSectionStatus.ready);
      expect(vm.virtualTryOnStatus, HomeSectionStatus.ready);
      expect(vm.topRatedStatus, HomeSectionStatus.ready);
      expect(vm.topRatedFurnitureDecorStatus, HomeSectionStatus.ready);
      expect(vm.featuredStatus, HomeSectionStatus.ready);
      for (final s in [
        vm.newArrivals,
        vm.arEnabledProducts,
        vm.virtualTryOnCollection,
        vm.topRated,
        vm.topRatedFurnitureDecor,
        vm.featuredProducts,
      ]) {
        expect(s.length, lessThanOrEqualTo(3));
      }
    });

    test('New Arrivals is ordered by genuine addedDate, newest first, and '
        'excludes epoch(0) (missing) dates', () async {
      await db.addProduct(
        _product('brand-new', addedDate: DateTime(2099, 1, 3)),
      );
      await db.addProduct(
        _product('older-new', addedDate: DateTime(2099, 1, 1)),
      );
      await db.addProduct(
        _product('no-date', addedDate: DateTime.fromMillisecondsSinceEpoch(0)),
      );
      await vm.loadHomeData();

      final ids = vm.newArrivals.map((p) => p.id).toList();
      expect(ids.first, 'brand-new');
      expect(ids[1], 'older-new');
      expect(ids.contains('no-date'), false);
    });

    test('editing a product (title change) does not move it in New Arrivals — '
        'addedDate is preserved through the update', () async {
      await db.addProduct(
        _product('keep-date', addedDate: DateTime(2099, 6, 1)),
      );
      await vm.loadHomeData();
      expect(vm.newArrivals.first.id, 'keep-date');

      await db.updateProduct(
        db.getProductById('keep-date').copyWith(title: 'Renamed'),
      );
      // _onDbChanged recomputed synchronously.
      expect(vm.newArrivals.first.id, 'keep-date');
      expect(vm.newArrivals.first.title, 'Renamed');
    });

    test('AR Enabled shows only published + active products with a renderable '
        'AR model — never a bare roomAr flag', () async {
      await db.addProduct(
        _product(
          'ar-ok',
          experience: ProductExperienceType.roomAr,
          arMetadata: _renderableAr,
          addedDate: DateTime(2099, 1, 1),
        ),
      );
      await db.addProduct(
        _product(
          'ar-no-model',
          experience: ProductExperienceType.roomAr,
          addedDate: DateTime(2099, 1, 2),
        ),
      );
      await db.addProduct(
        _product(
          'ar-draft',
          experience: ProductExperienceType.roomAr,
          arMetadata: _renderableAr,
          status: ProductPublicationStatus.draft,
          addedDate: DateTime(2099, 1, 3),
        ),
      );
      await vm.loadHomeData();

      final ids = vm.arEnabledProducts.map((p) => p.id).toSet();
      expect(ids.contains('ar-ok'), true);
      expect(ids.contains('ar-no-model'), false);
      expect(ids.contains('ar-draft'), false);
      expect(vm.arEnabledProducts.every((p) => p.arEnabled), true);
    });

    test('Virtual Try-On shows only published + active isVirtualTryOnEnabled '
        'products', () async {
      await db.addProduct(
        _product(
          'vto-ok',
          experience: ProductExperienceType.virtualTryOn,
          addedDate: DateTime(2099, 1, 1),
        ),
      );
      await db.addProduct(
        _product(
          'vto-draft',
          experience: ProductExperienceType.virtualTryOn,
          status: ProductPublicationStatus.draft,
          addedDate: DateTime(2099, 1, 2),
        ),
      );
      await vm.loadHomeData();

      final ids = vm.virtualTryOnCollection.map((p) => p.id).toSet();
      expect(ids.contains('vto-ok'), true);
      expect(ids.contains('vto-draft'), false);
      expect(vm.virtualTryOnCollection.every((p) => p.tryOnEnabled), true);
    });

    test(
      'Top Rated / Top Rated Furniture & Decor are a deterministic '
      'rating→reviewCount ranking (interim, not "Best Sellers"/"Popular")',
      () async {
        await db.addProduct(
          _product(
            'best',
            rating: 5.0,
            reviewCount: 999,
            kind: ProductCategory.decor,
          ),
        );
        await db.addProduct(
          _product(
            'worst',
            rating: 0.1,
            reviewCount: 0,
            kind: ProductCategory.decor,
          ),
        );
        await vm.loadHomeData();

        expect(vm.topRated.first.id, 'best');
        expect(vm.topRatedFurnitureDecor.first.id, 'best');
      },
    );

    test('sections recompute reactively when the catalogue changes', () async {
      await vm.loadHomeData();
      final before = vm.newArrivals.map((p) => p.id).toList();

      await db.addProduct(
        _product('just-added', addedDate: DateTime(2099, 12, 31)),
      );

      expect(vm.newArrivals.first.id, 'just-added');
      expect(vm.newArrivals.map((p) => p.id).toList(), isNot(before));
    });

    test(
      'favourite toggles never recompute or reorder the derived sections',
      () async {
        await vm.loadHomeData();
        final snapshot = vm.newArrivals.map((p) => p.id).toList();

        await vm.toggleFavorite(snapshot.first);

        expect(vm.newArrivals.map((p) => p.id).toList(), snapshot);
      },
    );
  });

  group('HomeViewModel — independent section failure & retry', () {
    test('a Categories failure sets ONLY categoriesStatus=error and never '
        'blanks the product sections or the whole screen', () async {
      final db = MockCommerceDatabase();
      final repo = _CategoriesFailRepository();
      final vm = HomeViewModel(
        repo,
        MockProductDetailsRepository(db, simulateDelay: false),
        _shopping(),
        db,
      );

      await vm.loadHomeData();

      expect(vm.categoriesStatus, HomeSectionStatus.error);
      expect(vm.hasError, true);
      expect(vm.newArrivalsStatus, HomeSectionStatus.ready);
      expect(vm.topRatedStatus, HomeSectionStatus.ready);
      expect(vm.showFullScreenError, false);
    });

    test('retryCategories recovers just that section, product sections '
        'untouched', () async {
      final db = MockCommerceDatabase();
      final repo = _CategoriesFailRepository();
      final vm = HomeViewModel(
        repo,
        MockProductDetailsRepository(db, simulateDelay: false),
        _shopping(),
        db,
      );
      await vm.loadHomeData();
      expect(vm.categoriesStatus, HomeSectionStatus.error);

      repo.healed = true;
      await vm.retryCategories();

      expect(vm.categoriesStatus, HomeSectionStatus.ready);
      expect(vm.categories, isNotEmpty);
    });

    test('full-screen error + Retry ONLY when Categories fail AND the '
        'catalogue is empty; recovers on retry', () async {
      final db = _EmptyCommerceDatabase();
      final repo = _CategoriesFailRepository();
      final vm = HomeViewModel(
        repo,
        MockProductDetailsRepository(
          MockCommerceDatabase(),
          simulateDelay: false,
        ),
        _shopping(),
        db,
      );

      await vm.loadHomeData();
      expect(vm.showFullScreenError, true);

      repo.healed = true;
      await vm.retry();
      expect(vm.showFullScreenError, false);
      expect(vm.hasError, false);
    });

    test(
      'concurrent loadHomeData calls collapse into one in-flight attempt',
      () async {
        final db = MockCommerceDatabase();
        final repo = _CategoriesFailRepository();
        final vm = HomeViewModel(
          repo,
          MockProductDetailsRepository(db, simulateDelay: false),
          _shopping(),
          db,
        );

        await Future.wait([
          vm.loadHomeData(),
          vm.loadHomeData(),
          vm.loadHomeData(),
        ]);

        expect(repo.categoriesCalls, 1);
      },
    );

    test('a repeated failing categories load stays retryable', () async {
      final db = MockCommerceDatabase();
      final repo = _CategoriesFailRepository();
      final vm = HomeViewModel(
        repo,
        MockProductDetailsRepository(db, simulateDelay: false),
        _shopping(),
        db,
      );
      await vm.loadHomeData();
      await vm.retryCategories();
      await vm.retryCategories();
      expect(vm.categoriesStatus, HomeSectionStatus.error);

      repo.healed = true;
      await vm.retryCategories();
      expect(vm.categoriesStatus, HomeSectionStatus.ready);
    });
  });
}
