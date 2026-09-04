import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/product_firestore_mapper.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_publication_status.dart';

void main() {
  group('ProductModel <-> Firestore mapping', () {
    test('every MockCommerceDatabase seed product round-trips through '
        'toFirestoreMap/productModelFromFirestore with every field intact', () {
      final products = MockCommerceDatabase().products;
      expect(products, isNotEmpty);

      for (final original in products) {
        final map = original.toFirestoreMap();
        final restored = productModelFromFirestore(original.id, map);

        expect(restored.id, original.id, reason: original.id);
        expect(restored.sku, original.sku, reason: original.id);
        expect(restored.title, original.title, reason: original.id);
        expect(restored.description, original.description, reason: original.id);
        expect(restored.categoryId, original.categoryId, reason: original.id);
        expect(
          restored.categoryKind,
          original.categoryKind,
          reason: original.id,
        );
        expect(restored.subcategory, original.subcategory, reason: original.id);
        expect(restored.priceAmount, original.priceAmount, reason: original.id);
        expect(
          restored.originalPriceAmount,
          original.originalPriceAmount,
          reason: original.id,
        );
        expect(
          restored.stockQuantity,
          original.stockQuantity,
          reason: original.id,
        );
        expect(restored.isActive, original.isActive, reason: original.id);
        expect(
          restored.showInCatalog,
          original.showInCatalog,
          reason: original.id,
        );
        expect(
          restored.publicationStatus,
          original.publicationStatus,
          reason: original.id,
        );
        expect(
          restored.mainImage.path,
          original.mainImage.path,
          reason: original.id,
        );
        expect(
          restored.galleryMedia.map((m) => m.path).toList(),
          original.galleryMedia.map((m) => m.path).toList(),
          reason: original.id,
        );
        expect(
          restored.experienceType,
          original.experienceType,
          reason: original.id,
        );
        expect(
          restored.vtoModelType,
          original.vtoModelType,
          reason: original.id,
        );
        expect(
          restored.availableColors,
          original.availableColors,
          reason: original.id,
        );
        expect(
          restored.availableSizes,
          original.availableSizes,
          reason: original.id,
        );
        expect(
          restored.defaultColor,
          original.defaultColor,
          reason: original.id,
        );
        expect(restored.defaultSize, original.defaultSize, reason: original.id);
        expect(
          restored.specifications.length,
          original.specifications.length,
          reason: original.id,
        );
        expect(
          restored.deliveryEstimate,
          original.deliveryEstimate,
          reason: original.id,
        );
        expect(restored.warranty, original.warranty, reason: original.id);
        expect(
          restored.recommendationRank,
          original.recommendationRank,
          reason: original.id,
        );
        expect(
          restored.popularityScore,
          original.popularityScore,
          reason: original.id,
        );
        expect(
          restored.addedDate.millisecondsSinceEpoch,
          original.addedDate.millisecondsSinceEpoch,
          reason: original.id,
        );
        expect(restored.rating, original.rating, reason: original.id);
        expect(restored.reviewCount, original.reviewCount, reason: original.id);
        expect(
          restored.arModelAssetPath,
          original.arModelAssetPath,
          reason: original.id,
        );
        // The legacy top-level `arScale` mirror is deliberately overwritten by
        // `arMetadata.scale` on write (tracker §2.10), so for a product with a
        // production contract it round-trips to the contract's scale, not the
        // original (usually null) legacy value.
        expect(
          restored.arScale,
          original.arMetadata != null
              ? original.arMetadata!.scale
              : original.arScale,
          reason: original.id,
        );
        expect(restored.arMetadata, original.arMetadata, reason: original.id);
        expect(
          restored.vtoGarmentAssetPath,
          original.vtoGarmentAssetPath,
          reason: original.id,
        );
      }
    });

    test('exactly the four physically-approved products carry a production AR '
        'contract (R13/R14/R15); every other product has none', () {
      const arIds = {
        'luna-accent-chair',
        'glass-coffee-table',
        'modern-table-lamp',
        'luna-3-seater-sofa',
      };
      for (final p in MockCommerceDatabase().products) {
        if (arIds.contains(p.id)) {
          expect(p.arMetadata, isNotNull, reason: p.id);
          expect(p.arMetadata!.isRenderable, isTrue, reason: p.id);
          expect(p.hasRenderableArModel, isTrue, reason: p.id);
          expect(
            p.arMetadata!.storagePath,
            'products/${p.id}/ar/model-v1.glb',
            reason: p.id,
          );
        } else {
          expect(p.arMetadata, isNull, reason: p.id);
        }
      }
    });

    test('a missing/malformed publicationStatus never defaults to published '
        '(safety-critical: must never accidentally leak a bad document to '
        'customers)', () {
      final restored = productModelFromFirestore('p1', {
        'title': 'Broken doc',
        // publicationStatus intentionally absent
      });
      expect(restored.publicationStatus, ProductPublicationStatus.draft);

      final restoredMalformed = productModelFromFirestore('p2', {
        'publicationStatus': 'not-a-real-status',
      });
      expect(
        restoredMalformed.publicationStatus,
        ProductPublicationStatus.draft,
      );
    });

    test('null optional fields survive the round trip as null', () {
      final product = ProductModel(
        id: 'p1',
        sku: 'SKU-1',
        title: 'Plain Product',
        description: 'desc',
        categoryId: 'decor',
        categoryKind: ProductCategory.decor,
        subcategory: 'sub',
        priceAmount: 1000,
        // originalPriceAmount, warranty, vtoModelType, arModelAssetPath,
        // arScale, vtoGarmentAssetPath, defaultColor, defaultSize all left
        // unset (null) - this is the case being tested.
        stockQuantity: 5,
        mainImage: const ProductImageRef(path: 'assets/x.png'),
        experienceType: ProductExperienceType.none,
        deliveryEstimate: '3-5 days',
        addedDate: DateTime(2026, 1, 1),
      );

      final restored = productModelFromFirestore(
        'p1',
        product.toFirestoreMap(),
      );

      expect(restored.originalPriceAmount, isNull);
      expect(restored.warranty, isNull);
      expect(restored.vtoModelType, isNull);
      expect(restored.arModelAssetPath, isNull);
      expect(restored.arScale, isNull);
      expect(restored.arMetadata, isNull);
      expect(restored.vtoGarmentAssetPath, isNull);
      expect(restored.defaultColor, isNull);
      expect(restored.defaultSize, isNull);
      expect(restored.availableColors, isEmpty);
      expect(restored.availableSizes, isEmpty);
    });

    test('Phase 8.8b dual-read: a legacy-shaped doc (only "category", no '
        '"categoryId"/"categoryKind") still reads correctly', () {
      final restored = productModelFromFirestore('legacy-1', {
        'title': 'Legacy Product',
        'category': 'decor',
        // categoryId/categoryKind intentionally absent - this is the shape
        // every live product had before the Phase 8.8b backfill script (or
        // an Admin edit) runs.
      });

      expect(restored.categoryId, 'decor');
      expect(restored.categoryKind, ProductCategory.decor);
    });

    test('a missing/malformed categoryKind never defaults to '
        'ProductCategory.all (a UI-only sentinel, never a real taxonomy '
        'value) - falls back to furniture instead', () {
      final missing = productModelFromFirestore('p1', {'title': 'No cat'});
      expect(missing.categoryKind, ProductCategory.furniture);

      final malformed = productModelFromFirestore('p2', {
        'categoryKind': 'not-a-real-kind',
      });
      expect(malformed.categoryKind, ProductCategory.furniture);
    });

    test('categoryId/categoryKind take precedence over a stale legacy '
        '"category" field when both are present', () {
      final restored = productModelFromFirestore('mixed-1', {
        'title': 'Mixed',
        'category': 'furniture',
        'categoryId': 'outdoor-furniture',
        'categoryKind': 'furniture',
      });
      expect(restored.categoryId, 'outdoor-furniture');
    });

    group('Phase 8.11 lastStockUpdatedAt', () {
      ProductModel baseProduct({DateTime? lastStockUpdatedAt}) => ProductModel(
        id: 'p1',
        sku: 'SKU-1',
        title: 'Product',
        description: 'desc',
        categoryId: 'decor',
        categoryKind: ProductCategory.decor,
        subcategory: 'sub',
        priceAmount: 1000,
        stockQuantity: 5,
        lastStockUpdatedAt: lastStockUpdatedAt,
        mainImage: const ProductImageRef(path: 'assets/x.png'),
        experienceType: ProductExperienceType.none,
        deliveryEstimate: '3-5 days',
        addedDate: DateTime(2026, 1, 1),
      );

      test('a doc with no lastStockUpdatedAt maps to null (never the epoch '
          'sentinel) - "never updated" is a real, displayable state', () {
        final restored = productModelFromFirestore('p1', {'title': 'No stamp'});
        expect(restored.lastStockUpdatedAt, isNull);
      });

      test('a present Timestamp round-trips to the same instant', () {
        final when = DateTime(2026, 8, 27, 14, 30, 15);
        final restored = productModelFromFirestore('p1', {
          'lastStockUpdatedAt': Timestamp.fromDate(when),
        });
        expect(
          restored.lastStockUpdatedAt!.millisecondsSinceEpoch,
          when.millisecondsSinceEpoch,
        );
      });

      test('a malformed (non-Timestamp) value maps to null, not a throw', () {
        final restored = productModelFromFirestore('p1', {
          'lastStockUpdatedAt': 'not-a-timestamp',
        });
        expect(restored.lastStockUpdatedAt, isNull);
      });

      test('toFirestoreMap OMITS the key when null, so a full-document .set() '
          '(addProduct/updateProduct) can never persist an explicit null and '
          'erase a live server value', () {
        final map = baseProduct().toFirestoreMap();
        expect(map.containsKey('lastStockUpdatedAt'), isFalse);
      });

      test(
        'toFirestoreMap writes a Timestamp when set, and it round-trips',
        () {
          final when = DateTime(2026, 8, 27, 9, 0, 0);
          final map = baseProduct(lastStockUpdatedAt: when).toFirestoreMap();
          expect(map['lastStockUpdatedAt'], isA<Timestamp>());

          final restored = productModelFromFirestore('p1', map);
          expect(
            restored.lastStockUpdatedAt!.millisecondsSinceEpoch,
            when.millisecondsSinceEpoch,
          );
        },
      );
    });

    group('Phase 9.2 R11/R12 arMetadata', () {
      const sha =
          'efd400046b265fd49d8d2b0382d378d230d625cb879740a3ef0697ca86c0d187';

      ProductModel productWithAr(ProductArMetadata? ar) => ProductModel(
        id: 'luna-3-seater-sofa',
        sku: 'SKU-1',
        title: 'Sofa',
        description: 'desc',
        categoryId: 'furniture',
        categoryKind: ProductCategory.furniture,
        subcategory: 'Sofas',
        priceAmount: 20000,
        stockQuantity: 5,
        mainImage: const ProductImageRef(path: 'assets/x.png'),
        experienceType: ProductExperienceType.roomAr,
        deliveryEstimate: '3-5 days',
        addedDate: DateTime(2026, 1, 1),
        arScale: 1.0,
        arMetadata: ar,
      );

      const validAr = ProductArMetadata(
        storagePath: 'products/luna-3-seater-sofa/ar/model-v1.glb',
        modelVersion: '1',
        sha256: sha,
        widthM: 2.65,
        depthM: 1.65,
        heightM: 0.82,
      );

      test('a product with a valid contract round-trips it intact', () {
        final map = productWithAr(validAr).toFirestoreMap();
        expect(
          map['arModelStoragePath'],
          'products/luna-3-seater-sofa/ar/model-v1.glb',
        );
        expect(map['arModelSha256'], sha);
        expect(map['arWidthM'], 2.65);

        final restored = productModelFromFirestore('luna-3-seater-sofa', map);
        expect(restored.arMetadata, validAr);
        expect(restored.arMetadata!.isRenderable, isTrue);
        expect(restored.hasRenderableArModel, isTrue);
      });

      test('an existing doc with NO arModelStoragePath keeps arMetadata null '
          'and its legacy admin fields intact (backward compatible)', () {
        final restored = productModelFromFirestore('legacy', {
          'title': 'Legacy AR product',
          'experienceType': 'roomAr',
          'arModelAssetPath': 'chair_model.glb',
          'arScale': 1.25,
        });
        expect(restored.arMetadata, isNull);
        expect(restored.hasRenderableArModel, isFalse);
        expect(restored.arModelAssetPath, 'chair_model.glb');
        expect(restored.arScale, 1.25);
      });

      test('a present-but-malformed contract parses as a non-renderable object '
          '(fail safe + honest), never as "no AR"', () {
        final restored = productModelFromFirestore('broken', {
          'title': 'Broken AR',
          'experienceType': 'roomAr',
          'arModelStoragePath':
              'https://cdn.example.com/sofa.glb', // URL, not a Storage path
          'arModelFormat': 'glb',
          'arModelVersion': '1',
          'arModelSha256': sha,
          'arWidthM': 2.65,
          'arDepthM': 1.65,
          'arHeightM': 0.82,
          'arScaleContract': ProductArMetadata.currentScaleContract,
        });
        expect(restored.arMetadata, isNotNull);
        expect(restored.arMetadata!.isRenderable, isFalse);
        expect(restored.hasRenderableArModel, isFalse);
      });

      test('the contract\'s arScale overrides the legacy mirror on write', () {
        final ar = validAr.copyWith(scale: 1.3);
        final map = productWithAr(ar).toFirestoreMap(); // legacy arScale = 1.0
        expect(map['arScale'], 1.3);
      });

      test('toFirestoreMap omits every ar* contract key when arMetadata is '
          'null, so non-AR and pre-9.2 docs are untouched', () {
        final map = productWithAr(null).toFirestoreMap();
        for (final k in const [
          'arModelStoragePath',
          'arModelFormat',
          'arModelVersion',
          'arModelSha256',
          'arWidthM',
          'arDepthM',
          'arHeightM',
          'arScaleContract',
        ]) {
          expect(map.containsKey(k), isFalse, reason: k);
        }
      });
    });
  });
}
