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
import 'package:twin_ar/features/home/models/category_model.dart';
import 'package:twin_ar/features/home/models/home_banner_model.dart';
import 'package:twin_ar/features/home/repositories/home_repository.dart';
import 'package:twin_ar/features/home/repositories/mock_home_repository.dart';
import 'package:twin_ar/features/home/repositories/mock_product_stats_repository.dart';
import 'package:twin_ar/features/home/viewmodels/home_viewmodel.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_recently_viewed_repository.dart';

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
  bool isFeatured = false,
  int featuredRank = ProductModel.defaultFeaturedRank,
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
  isFeatured: isFeatured,
  featuredRank: featuredRank,
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

HomeViewModel _vm(
  CommerceDatabase db, {
  HomeRepository? repo,
  MockProductStatsRepository? stats,
  MockRecentlyViewedRepository? recentlyViewed,
}) => HomeViewModel(
  repo ?? MockHomeRepository(),
  MockProductDetailsRepository(
    db is MockCommerceDatabase ? db : MockCommerceDatabase(),
    simulateDelay: false,
  ),
  _shopping(),
  db,
  stats ?? MockProductStatsRepository(),
  recentlyViewed ?? MockRecentlyViewedRepository(signedIn: false),
);

void main() {
  group('HomeViewModel — cache-derived sections (Stage 1 regressions)', () {
    late MockCommerceDatabase db;
    late HomeViewModel vm;

    setUp(() {
      db = MockCommerceDatabase();
      vm = _vm(db);
    });

    test('initial state: loading', () {
      expect(vm.isLoading, true);
      expect(vm.cartCount, 0);
    });

    test('loadHomeData populates every section from real data', () async {
      await vm.loadHomeData();

      expect(vm.isLoading, false);
      expect(vm.banners, isNotEmpty);
      expect(vm.categories, isNotEmpty);
      expect(vm.newArrivalsStatus, HomeSectionStatus.ready);
      expect(vm.arEnabledStatus, HomeSectionStatus.ready);
      expect(vm.virtualTryOnStatus, HomeSectionStatus.ready);
      expect(vm.bestSellersStatus, HomeSectionStatus.ready);
      expect(vm.popularFurnitureDecorStatus, HomeSectionStatus.ready);
      for (final s in [
        vm.newArrivals,
        vm.arEnabledProducts,
        vm.virtualTryOnCollection,
        vm.bestSellers,
        vm.popularFurnitureDecor,
        vm.featuredProducts,
      ]) {
        expect(s.length, lessThanOrEqualTo(3));
      }
    });

    test('New Arrivals is ordered by genuine addedDate, newest first, and '
        'excludes epoch(0) dates', () async {
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

    test('AR Enabled shows only published+active products with a renderable '
        'AR model', () async {
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

    test('Virtual Try-On shows only published+active isVirtualTryOnEnabled '
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
      'favourite toggles never recompute or reorder the derived sections',
      () async {
        await vm.loadHomeData();
        final snapshot = vm.newArrivals.map((p) => p.id).toList();
        await vm.toggleFavorite(snapshot.first);
        expect(vm.newArrivals.map((p) => p.id).toList(), snapshot);
      },
    );
  });

  group('HomeViewModel — Best Sellers (productStats.unitsSold + fallback)', () {
    test(
      'with genuine unitsSold data: ranks by sales, labels as real, '
      'resolves ids against the cache and skips misses/ineligibles',
      () async {
        final db = MockCommerceDatabase();
        await db.addProduct(_product('sofa', rating: 1.0));
        await db.addProduct(_product('rug', rating: 1.0));
        await db.addProduct(_product('lamp', rating: 1.0));
        await db.addProduct(
          _product('draft-hit', status: ProductPublicationStatus.draft),
        );
        final stats = MockProductStatsRepository(
          unitsSold: {
            'rug': 50,
            'sofa': 90,
            'lamp': 10,
            'draft-hit': 999, // ineligible → skipped
            'ghost-id': 500, // not in catalogue → skipped
          },
        );
        final vm = _vm(db, stats: stats);
        await vm.loadHomeData();

        expect(vm.bestSellersUsesRealSalesData, true);
        expect(vm.bestSellers.map((p) => p.id).toList(), [
          'sofa',
          'rug',
          'lamp',
        ]);
        expect(vm.bestSellersSeeAllIds.take(3).toList(), [
          'sofa',
          'rug',
          'lamp',
        ]);
      },
    );

    test('one genuine sale is enough to switch to the real ranking', () async {
      final db = MockCommerceDatabase();
      await db.addProduct(_product('only-seller'));
      final vm = _vm(
        db,
        stats: MockProductStatsRepository(unitsSold: {'only-seller': 1}),
      );
      await vm.loadHomeData();
      expect(vm.bestSellersUsesRealSalesData, true);
      expect(vm.bestSellers.single.id, 'only-seller');
    });

    test(
      'no sales data → honest rating fallback, flagged as NOT real sales',
      () async {
        final db = _EmptyCommerceDatabase();
        await db.addProduct(_product('a', rating: 5.0, reviewCount: 9));
        await db.addProduct(_product('b', rating: 4.0, reviewCount: 100));
        await db.addProduct(_product('c', rating: 2.0, reviewCount: 1));
        final vm = _vm(db); // empty stats
        await vm.loadHomeData();

        expect(vm.bestSellersUsesRealSalesData, false);
        expect(vm.bestSellers.map((p) => p.id).toList(), ['a', 'b', 'c']);
        expect(vm.bestSellersStatus, HomeSectionStatus.ready);
      },
    );

    test(
      'a stats read that throws is swallowed → rating fallback, no error',
      () async {
        final db = MockCommerceDatabase();
        final vm = _vm(
          db,
          stats: MockProductStatsRepository(throwOnRead: true),
        );
        await vm.loadHomeData();

        expect(vm.bestSellersUsesRealSalesData, false);
        expect(vm.bestSellers, isNotEmpty);
        expect(vm.hasError, false);
        expect(vm.showFullScreenError, false);
      },
    );

    test(
      'deterministic tie-break: equal sales fall back to id order',
      () async {
        final db = MockCommerceDatabase();
        await db.addProduct(_product('m'));
        await db.addProduct(_product('a'));
        await db.addProduct(_product('z'));
        final vm = _vm(
          db,
          stats: MockProductStatsRepository(
            unitsSold: {'m': 7, 'a': 7, 'z': 7},
          ),
        );
        await vm.loadHomeData();
        expect(vm.bestSellers.map((p) => p.id).toList(), ['a', 'm', 'z']);
      },
    );
  });

  group('HomeViewModel — Popular Furniture & Decor (favoriteCount)', () {
    test(
      'ranks eligible furniture/decor by favoriteCount, real label',
      () async {
        final db = MockCommerceDatabase();
        await db.addProduct(_product('chair', kind: ProductCategory.furniture));
        await db.addProduct(_product('vase', kind: ProductCategory.decor));
        await db.addProduct(_product('shirt', kind: ProductCategory.clothing));
        final vm = _vm(
          db,
          stats: MockProductStatsRepository(
            favoriteCount: {'shirt': 99, 'vase': 20, 'chair': 40},
          ),
        );
        await vm.loadHomeData();

        expect(vm.popularUsesRealFavoriteData, true);
        // clothing is filtered out even though it has the most favourites
        expect(vm.popularFurnitureDecor.map((p) => p.id).toList(), [
          'chair',
          'vase',
        ]);
      },
    );

    test('favourites only on non-furniture/decor → rating fallback', () async {
      final db = MockCommerceDatabase();
      await db.addProduct(
        _product('tshirt', kind: ProductCategory.clothing, rating: 1),
      );
      await db.addProduct(
        _product('goodrug', kind: ProductCategory.decor, rating: 5),
      );
      final vm = _vm(
        db,
        stats: MockProductStatsRepository(favoriteCount: {'tshirt': 50}),
      );
      await vm.loadHomeData();

      expect(vm.popularUsesRealFavoriteData, false);
      expect(vm.popularFurnitureDecor.first.id, 'goodrug');
    });
  });

  group('HomeViewModel — Featured (isFeatured / featuredRank)', () {
    test('shows only isFeatured published+active products ordered by '
        'featuredRank, then hides when none', () async {
      final db = _EmptyCommerceDatabase();
      final vm = _vm(db);
      await vm.loadHomeData();
      expect(vm.featuredStatus, HomeSectionStatus.empty); // hidden

      await db.addProduct(
        _product('feat-c', isFeatured: true, featuredRank: 30),
      );
      await db.addProduct(
        _product('feat-a', isFeatured: true, featuredRank: 10),
      );
      await db.addProduct(
        _product('feat-b', isFeatured: true, featuredRank: 20),
      );
      await db.addProduct(
        _product(
          'feat-draft',
          isFeatured: true,
          featuredRank: 1,
          status: ProductPublicationStatus.draft,
        ),
      );
      await db.addProduct(_product('not-featured'));

      expect(vm.featuredStatus, HomeSectionStatus.ready);
      expect(vm.featuredProducts.map((p) => p.id).toList(), [
        'feat-a',
        'feat-b',
        'feat-c',
      ]);
      expect(vm.featuredSeeAllIds, ['feat-a', 'feat-b', 'feat-c']);
      expect(
        vm.featuredProducts.map((p) => p.id),
        isNot(contains('feat-draft')),
      );
    });

    test('equal featuredRank falls back to newest, then id', () async {
      final db = MockCommerceDatabase();
      await db.addProduct(
        _product(
          'old',
          isFeatured: true,
          featuredRank: 5,
          addedDate: DateTime(2020),
        ),
      );
      await db.addProduct(
        _product(
          'new',
          isFeatured: true,
          featuredRank: 5,
          addedDate: DateTime(2099),
        ),
      );
      final vm = _vm(db);
      await vm.loadHomeData();
      expect(vm.featuredProducts.map((p) => p.id).toList(), ['new', 'old']);
    });

    test('an inactive featured product never appears on Home', () async {
      final db = _EmptyCommerceDatabase();
      await db.addProduct(
        _product('feat-active', isFeatured: true, featuredRank: 10),
      );
      await db.addProduct(
        _product(
          'feat-inactive',
          isFeatured: true,
          featuredRank: 1,
          isActive: false,
        ),
      );
      final vm = _vm(db);
      await vm.loadHomeData();
      expect(vm.featuredProducts.map((p) => p.id).toList(), ['feat-active']);
    });

    test(
      'unfeaturing / unpublishing a product reactively removes it from '
      'Featured (via _onDbChanged), section hides when the last one goes',
      () async {
        final db = MockCommerceDatabase();
        await db.addProduct(
          _product('only-featured', isFeatured: true, featuredRank: 10),
        );
        final vm = _vm(db);
        await vm.loadHomeData();
        expect(vm.featuredProducts.single.id, 'only-featured');

        // unfeature — same product, isFeatured flipped off
        await db.updateProduct(
          db.getProductById('only-featured').copyWith(isFeatured: false),
        );
        expect(vm.featuredProducts, isEmpty);
        expect(vm.featuredStatus, HomeSectionStatus.empty);

        // re-feature, then unpublish → also gone
        await db.updateProduct(
          db.getProductById('only-featured').copyWith(isFeatured: true),
        );
        expect(vm.featuredProducts.single.id, 'only-featured');
        await db.updateProduct(
          db
              .getProductById('only-featured')
              .copyWith(publicationStatus: ProductPublicationStatus.draft),
        );
        expect(vm.featuredProducts, isEmpty);
      },
    );
  });

  group('HomeViewModel — Recently Viewed', () {
    test(
      'latest-first, deduped, resolved against the cache, top 3 shown',
      () async {
        final db = MockCommerceDatabase();
        for (final id in ['p1', 'p2', 'p3', 'p4', 'p5']) {
          await db.addProduct(_product(id));
        }
        final rv = MockRecentlyViewedRepository();
        // recorded p1..p5, then re-view p2 (moves to front)
        for (final id in ['p1', 'p2', 'p3', 'p4', 'p5', 'p2']) {
          await rv.recordView(id);
        }
        final vm = _vm(db, recentlyViewed: rv);
        await vm.loadHomeData();

        expect(vm.recentlyViewedStatus, HomeSectionStatus.ready);
        expect(vm.recentlyViewedProducts.map((p) => p.id).toList(), [
          'p2',
          'p5',
          'p4',
        ]);
        expect(vm.recentlyViewedHasSeeAll, true); // 5 eligible > 3
      },
    );

    test(
      'excludes deleted/draft/inactive; hides section when nothing resolves',
      () async {
        final db = MockCommerceDatabase();
        await db.addProduct(
          _product('draft-v', status: ProductPublicationStatus.draft),
        );
        final rv = MockRecentlyViewedRepository()
          ..recordView('draft-v')
          ..recordView('never-existed');
        final vm = _vm(db, recentlyViewed: rv);
        await vm.loadHomeData();

        expect(vm.recentlyViewedStatus, HomeSectionStatus.empty);
        expect(vm.recentlyViewedProducts, isEmpty);
      },
    );

    test('See all is hidden at exactly 3 eligible items', () async {
      final db = MockCommerceDatabase();
      for (final id in ['a', 'b', 'c']) {
        await db.addProduct(_product(id));
      }
      final rv = MockRecentlyViewedRepository()
        ..recordView('a')
        ..recordView('b')
        ..recordView('c');
      final vm = _vm(db, recentlyViewed: rv);
      await vm.loadHomeData();

      expect(vm.recentlyViewedProducts.length, 3);
      expect(vm.recentlyViewedHasSeeAll, false);
    });

    test('signed-out history is empty → section hidden, no error', () async {
      final db = MockCommerceDatabase();
      final vm = _vm(
        db,
        recentlyViewed: MockRecentlyViewedRepository(signedIn: false),
      );
      await vm.loadHomeData();
      expect(vm.recentlyViewedStatus, HomeSectionStatus.empty);
      expect(vm.hasError, false);
    });

    test(
      'a throwing history read is swallowed → section hidden, no error',
      () async {
        final db = MockCommerceDatabase();
        final vm = _vm(
          db,
          recentlyViewed: MockRecentlyViewedRepository()..throwOnRead = true,
        );
        await vm.loadHomeData();
        expect(vm.recentlyViewedStatus, HomeSectionStatus.empty);
        expect(vm.hasError, false);
        expect(vm.showFullScreenError, false);
      },
    );

    test('reloadDynamicSections picks up a newly-viewed product', () async {
      final db = MockCommerceDatabase();
      await db.addProduct(_product('fresh'));
      final rv = MockRecentlyViewedRepository();
      final vm = _vm(db, recentlyViewed: rv);
      await vm.loadHomeData();
      expect(vm.recentlyViewedStatus, HomeSectionStatus.empty);

      await rv.recordView('fresh');
      await vm.reloadDynamicSections();

      expect(vm.recentlyViewedProducts.single.id, 'fresh');
    });
  });

  group('HomeViewModel — reactivity & section independence', () {
    test('sections recompute when the catalogue changes', () async {
      final db = MockCommerceDatabase();
      final vm = _vm(db);
      await vm.loadHomeData();
      final before = vm.newArrivals.map((p) => p.id).toList();

      await db.addProduct(
        _product('just-added', addedDate: DateTime(2099, 12, 31)),
      );

      expect(vm.newArrivals.first.id, 'just-added');
      expect(vm.newArrivals.map((p) => p.id).toList(), isNot(before));
    });

    test('best sellers re-resolve against the cache when a ranked product is '
        'unpublished', () async {
      final db = MockCommerceDatabase();
      await db.addProduct(_product('hot'));
      await db.addProduct(_product('warm'));
      final vm = _vm(
        db,
        stats: MockProductStatsRepository(unitsSold: {'hot': 100, 'warm': 5}),
      );
      await vm.loadHomeData();
      expect(vm.bestSellers.first.id, 'hot');

      await db.updateProduct(
        db.getProductById('hot').copyWith(isActive: false),
      );
      expect(vm.bestSellers.map((p) => p.id), isNot(contains('hot')));
    });

    test('a stats failure never blanks the whole screen', () async {
      final db = _EmptyCommerceDatabase();
      final vm = _vm(
        db,
        stats: MockProductStatsRepository(throwOnRead: true),
        recentlyViewed: MockRecentlyViewedRepository(signedIn: false),
      );
      await vm.loadHomeData();
      // Categories (MockHomeRepository) succeeded → no full-screen error even
      // though every product section is empty and stats threw.
      expect(vm.hasError, false);
      expect(vm.showFullScreenError, false);
    });
  });

  group('HomeViewModel — independent Categories failure & retry', () {
    test('a Categories failure sets ONLY categoriesStatus=error', () async {
      final db = MockCommerceDatabase();
      final repo = _CategoriesFailRepository();
      final vm = _vm(db, repo: repo);
      await vm.loadHomeData();

      expect(vm.categoriesStatus, HomeSectionStatus.error);
      expect(vm.hasError, true);
      expect(vm.newArrivalsStatus, HomeSectionStatus.ready);
      expect(vm.bestSellersStatus, HomeSectionStatus.ready);
      expect(vm.showFullScreenError, false);
    });

    test('retryCategories recovers just that section', () async {
      final db = MockCommerceDatabase();
      final repo = _CategoriesFailRepository();
      final vm = _vm(db, repo: repo);
      await vm.loadHomeData();
      expect(vm.categoriesStatus, HomeSectionStatus.error);

      repo.healed = true;
      await vm.retryCategories();

      expect(vm.categoriesStatus, HomeSectionStatus.ready);
      expect(vm.categories, isNotEmpty);
    });

    test(
      'full-screen error ONLY when Categories fail AND catalogue empty',
      () async {
        final db = _EmptyCommerceDatabase();
        final repo = _CategoriesFailRepository();
        final vm = _vm(db, repo: repo);

        await vm.loadHomeData();
        expect(vm.showFullScreenError, true);

        repo.healed = true;
        await vm.retry();
        expect(vm.showFullScreenError, false);
        expect(vm.hasError, false);
      },
    );

    test('concurrent loadHomeData calls collapse into one', () async {
      final db = MockCommerceDatabase();
      final repo = _CategoriesFailRepository();
      final vm = _vm(db, repo: repo);

      await Future.wait([
        vm.loadHomeData(),
        vm.loadHomeData(),
        vm.loadHomeData(),
      ]);

      expect(repo.categoriesCalls, 1);
    });
  });
}
