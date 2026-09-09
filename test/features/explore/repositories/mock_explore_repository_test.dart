import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/features/explore/repositories/mock_explore_repository.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_publication_status.dart';

void main() {
  late MockCommerceDatabase db;
  late MockExploreRepository repository;

  setUp(() {
    db = MockCommerceDatabase();
    repository = MockExploreRepository(db);
  });

  group('MockExploreRepository Tests', () {
    test(
      'showInCatalog=false no longer hides a product from Explore '
      '(Phase 9.3 pre-work - showInCatalog is not a customer Explore filter)',
      () async {
        final catalog = await repository.getCatalog();
        final sofa = catalog
            .where((p) => p.summary.id == 'luna-3-seater-sofa')
            .toList();
        expect(
          sofa.isNotEmpty,
          true,
          reason:
              'Luna sofa is showInCatalog=false but is published+active, so it '
              'is part of the full customer catalogue now',
        );
      },
    );

    test('includes active products with showInCatalog=true', () async {
      final catalog = await repository.getCatalog();
      final included = catalog
          .where((p) => p.summary.id == 'beige-ar-in-stock-2')
          .toList();
      expect(
        included.isNotEmpty,
        true,
        reason: 'Explore item should be included',
      );
    });

    test('excludes inactive products even if showInCatalog=true', () async {
      db.setProductActive('beige-ar-in-stock-2', false);
      final catalog = await repository.getCatalog();
      final included = catalog
          .where((p) => p.summary.id == 'beige-ar-in-stock-2')
          .toList();
      expect(
        included.isEmpty,
        true,
        reason: 'Inactive product should be excluded',
      );
    });

    test('catalog is the complete published+active set, not an arbitrary '
        'ceiling (no hardcoded count)', () async {
      final items = await repository.getCatalog();
      final expected = db.products
          .where(
            (p) =>
                p.isActive &&
                p.publicationStatus == ProductPublicationStatus.published,
          )
          .length;
      expect(items.length, expected);
      expect(
        items.length,
        greaterThan(36),
        reason:
            'the old showInCatalog-curated view capped Explore near 36; the '
            'full catalogue is larger',
      );
    });

    test('excludes products with publicationStatus=draft', () async {
      final draftProduct = ProductModel(
        id: 'draft-product-1',
        sku: 'TEST-001',
        title: 'Draft Product',
        description: 'Test',
        categoryId: 'furniture',
        categoryKind: ProductCategory.furniture,
        subcategory: 'Test',
        priceAmount: 1000,
        stockQuantity: 10,
        mainImage: const ProductImageRef(path: 'test.png'),
        experienceType: ProductExperienceType.none,
        addedDate: DateTime.now(),
        isActive: true,
        showInCatalog: true,
        publicationStatus: ProductPublicationStatus.draft,
        deliveryEstimate: '3 - 5 Days',
      );
      db.addProduct(draftProduct);

      final catalog = await repository.getCatalog();
      final included = catalog
          .where((p) => p.summary.id == 'draft-product-1')
          .toList();
      expect(included.isEmpty, true);
    });
  });
}
