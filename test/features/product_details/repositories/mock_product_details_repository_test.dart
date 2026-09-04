import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/home/repositories/mock_home_repository.dart';
import 'package:twin_ar/features/explore/repositories/mock_explore_repository.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';

void main() {
  late MockProductDetailsRepository repository;
  late MockHomeRepository homeRepository;
  late MockExploreRepository exploreRepository;

  setUp(() {
    repository = MockProductDetailsRepository(
      MockCommerceDatabase(),
      simulateDelay: false,
    );
    homeRepository = MockHomeRepository(MockCommerceDatabase());
    exploreRepository = MockExploreRepository(MockCommerceDatabase());
  });

  group('MockProductDetailsRepository Tests', () {
    test('Luna exact model matches target data', () async {
      final product = await repository.getProductDetails('luna-accent-chair');
      expect(product.summary.title, 'Luna Accent Chair');
      expect(product.categoryKind, ProductCategory.furniture);
      expect(product.subcategory, 'Accent Chairs');
      expect(product.experienceType, ProductExperienceType.roomAr);
      expect(product.summary.currentPrice, 'Rs 12,000/-');
      expect(product.summary.originalPrice, 'Rs 16,000/-');
      expect(product.deliveryEstimate, contains('20 - 24 May, 2025'));
    });

    test('Oxford exact model matches target data', () async {
      final product = await repository.getProductDetails('mens-oxford-shirt');
      expect(product.summary.title, 'Men\'s Oxford Shirt');
      expect(product.categoryKind, ProductCategory.clothing);
      expect(product.subcategory, 'Shirts');
      expect(product.experienceType, ProductExperienceType.virtualTryOn);
      expect(product.summary.currentPrice, 'Rs 2,200/-');
      expect(product.availableSizes, isNotEmpty);
      expect(product.defaultSize, isNotNull);
    });

    test('all Home unique product IDs resolve', () async {
      // Home uses multiple methods to generate data
      final featured = await homeRepository.getFeaturedProducts();
      final bestSellers = await homeRepository.getBestSellers();
      final newArrivals = await homeRepository.getNewArrivals();
      final popular = await homeRepository.getPopularFurniture();
      final recent = await homeRepository.getRecentlyViewed();

      final allIds = <String>{};

      for (var p in featured) {
        allIds.add(p.id);
      }
      for (var p in bestSellers) {
        allIds.add(p.id);
      }
      for (var p in newArrivals) {
        allIds.add(p.id);
      }
      for (var p in popular) {
        allIds.add(p.id);
      }
      for (var p in recent) {
        allIds.add(p.id);
      }

      for (var id in allIds) {
        final product = await repository.getProductDetails(id);
        expect(product.summary.id, id);
      }
    });

    test('all Explore product IDs resolve', () async {
      final catalog = await exploreRepository.getCatalog();
      for (var item in catalog) {
        final product = await repository.getProductDetails(item.summary.id);
        expect(product.summary.id, item.summary.id);
      }
    });

    test('unknown ID fails cleanly', () async {
      expect(
        () => repository.getProductDetails('definitely-invalid-product-id'),
        throwsStateError,
      );
    });

    test('experience-type semantics correct across explore products', () async {
      final catalog = await exploreRepository.getCatalog();
      for (var item in catalog) {
        final product = await repository.getProductDetails(item.summary.id);
        if (product.categoryKind == ProductCategory.clothing) {
          expect(
            product.experienceType,
            isNot(ProductExperienceType.roomAr),
            reason: 'Clothing cannot have roomAr',
          );
        } else {
          expect(
            product.experienceType,
            isNot(ProductExperienceType.virtualTryOn),
            reason: 'Non-clothing cannot have virtualTryOn',
          );
        }
      }
    });
  });
}
