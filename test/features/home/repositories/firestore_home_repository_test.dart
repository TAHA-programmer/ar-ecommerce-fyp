import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/features/home/repositories/firestore_home_repository.dart';

Future<void> _seed(
  FakeFirebaseFirestore firestore,
  String id, {
  String publicationStatus = 'published',
  bool isActive = true,
  int recommendationRank = 0,
  bool isRoomAr = false,
}) {
  return firestore.collection('products').doc(id).set({
    'sku': 'SKU-$id',
    'title': id,
    'description': '',
    'category': 'furniture',
    'subcategory': '',
    'priceAmount': 1000,
    'stockQuantity': 5,
    'isActive': isActive,
    'showInCatalog': true,
    'publicationStatus': publicationStatus,
    'mainImage': {'path': 'assets/x.png', 'source': 'asset', 'altText': ''},
    'galleryMedia': <Map<String, dynamic>>[],
    'experienceType': isRoomAr ? 'roomAr' : 'none',
    'availableColors': <String>[],
    'availableSizes': <String>[],
    'specifications': <Map<String, dynamic>>[],
    'deliveryEstimate': '3-5 days',
    'recommendationRank': recommendationRank,
    'popularityScore': 0,
    'addedDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'rating': 4.5,
    'reviewCount': 10,
  });
}

void main() {
  group('FirestoreHomeRepository', () {
    test('getFeaturedProducts returns only published+active products with '
        'recommendationRank == 10', () async {
      final firestore = FakeFirebaseFirestore();
      await _seed(firestore, 'featured-1', recommendationRank: 10);
      await _seed(
        firestore,
        'featured-but-draft',
        recommendationRank: 10,
        publicationStatus: 'draft',
      );
      await _seed(firestore, 'not-featured', recommendationRank: 20);
      final repository = FirestoreHomeRepository(firestore: firestore);

      final result = await repository.getFeaturedProducts();

      expect(result.map((p) => p.id).toList(), ['featured-1']);
    });

    test(
      'getBestSellers returns only the curated IDs, excluding a draft one',
      () async {
        final firestore = FakeFirebaseFirestore();
        await _seed(firestore, 'luna-3-seater-sofa');
        await _seed(firestore, 'boho-woven-rug');
        await _seed(
          firestore,
          'classic-blue-shirt',
          publicationStatus: 'draft',
        );
        await _seed(firestore, 'not-curated-at-all');
        final repository = FirestoreHomeRepository(firestore: firestore);

        final result = await repository.getBestSellers();

        expect(result.map((p) => p.id).toSet(), {
          'luna-3-seater-sofa',
          'boho-woven-rug',
        });
      },
    );

    test(
      'a curated ID that no longer exists is silently skipped - it never '
      'takes the whole rail (or Home) down. Regression: the AR rail hardcoded '
      'minimalist-bedroom-set, which was deleted; the old '
      'whereIn-on-documentId query then failed the ENTIRE query with '
      'permission-denied against the real rules (see the emulator test)',
      () async {
        final firestore = FakeFirebaseFirestore();
        await _seed(firestore, 'wooden-console', isRoomAr: true);
        await _seed(firestore, 'glass-coffee-table', isRoomAr: true);
        await _seed(firestore, 'velvet-armchair', isRoomAr: true);
        // 'minimalist-bedroom-set' deliberately NOT seeded (deleted from live)
        final repository = FirestoreHomeRepository(firestore: firestore);

        final result = await repository.getArEnabledProducts();

        expect(result.map((p) => p.id).toSet(), {
          'wooden-console',
          'glass-coffee-table',
          'velvet-armchair',
        });
      },
    );

    test('getArEnabledProducts no longer references the deleted '
        'minimalist-bedroom-set at all', () async {
      final firestore = FakeFirebaseFirestore();
      await _seed(firestore, 'minimalist-bedroom-set', isRoomAr: true);
      await _seed(firestore, 'wooden-console', isRoomAr: true);
      await _seed(firestore, 'glass-coffee-table', isRoomAr: true);
      await _seed(firestore, 'velvet-armchair', isRoomAr: true);
      final repository = FirestoreHomeRepository(firestore: firestore);

      final result = await repository.getArEnabledProducts();

      expect(result.map((p) => p.id).contains('minimalist-bedroom-set'), false);
      expect(result.length, 3);
    });

    test('a curated ID that is now a draft is skipped, not returned, and does '
        'not throw', () async {
      final firestore = FakeFirebaseFirestore();
      await _seed(firestore, 'luna-3-seater-sofa');
      await _seed(firestore, 'boho-woven-rug', publicationStatus: 'draft');
      await _seed(firestore, 'classic-blue-shirt', isActive: false);
      final repository = FirestoreHomeRepository(firestore: firestore);

      final result = await repository.getBestSellers();

      expect(result.map((p) => p.id).toList(), ['luna-3-seater-sofa']);
    });

    test('curated rail order is preserved', () async {
      final firestore = FakeFirebaseFirestore();
      await _seed(firestore, 'classic-blue-shirt');
      await _seed(firestore, 'luna-3-seater-sofa');
      await _seed(firestore, 'boho-woven-rug');
      final repository = FirestoreHomeRepository(firestore: firestore);

      final result = await repository.getBestSellers();

      // getBestSellers order: sofa, rug, shirt
      expect(result.map((p) => p.id).toList(), [
        'luna-3-seater-sofa',
        'boho-woven-rug',
        'classic-blue-shirt',
      ]);
    });

    test(
      'every curated ID missing returns an empty rail, not an error',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = FirestoreHomeRepository(firestore: firestore);

        expect(await repository.getRecentlyViewed(), isEmpty);
        expect(await repository.getPopularFurniture(), isEmpty);
        expect(await repository.getVirtualTryOnCollection(), isEmpty);
      },
    );

    test('getBanners returns the static content, not products', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirestoreHomeRepository(firestore: firestore);

      final banners = await repository.getBanners();

      expect(banners, isNotEmpty);
    });

    group('getCategories (Phase 8.8b - real Admin-managed categories)', () {
      Future<void> seedCategory(
        FakeFirebaseFirestore firestore,
        String id, {
        required String name,
        required bool isActive,
        required int sortOrder,
        String imageUrl = '',
        String kind = 'furniture',
      }) {
        return firestore.collection('categories').doc(id).set({
          'name': name,
          'key': id,
          'kind': kind,
          'imageUrl': imageUrl,
          'isActive': isActive,
          'sortOrder': sortOrder,
        });
      }

      test('returns only active categories, sorted client-side by sortOrder '
          '(single-field query only - no server orderBy, so no composite '
          'index is required)', () async {
        final firestore = FakeFirebaseFirestore();
        await seedCategory(
          firestore,
          'lighting',
          name: 'Lighting',
          isActive: true,
          sortOrder: 50,
        );
        await seedCategory(
          firestore,
          'furniture',
          name: 'Furniture',
          isActive: true,
          sortOrder: 10,
        );
        await seedCategory(
          firestore,
          'discontinued',
          name: 'Discontinued',
          isActive: false,
          sortOrder: 5,
        );
        final repository = FirestoreHomeRepository(firestore: firestore);

        final categories = await repository.getCategories();

        expect(categories.map((c) => c.id).toList(), ['furniture', 'lighting']);
      });

      test(
        'maps imageUrl (a Storage download URL) onto CategoryModel.imageUrl, '
        'leaving imageAssetPath empty - Home renders this via Image.network',
        () async {
          final firestore = FakeFirebaseFirestore();
          await seedCategory(
            firestore,
            'furniture',
            name: 'Furniture',
            isActive: true,
            sortOrder: 10,
            imageUrl: 'https://storage.example/furniture.png',
          );
          final repository = FirestoreHomeRepository(firestore: firestore);

          final categories = await repository.getCategories();

          expect(
            categories.single.imageUrl,
            'https://storage.example/furniture.png',
          );
          expect(categories.single.imageAssetPath, '');
        },
      );

      test('an empty categories collection returns an empty list, not an '
          'error', () async {
        final firestore = FakeFirebaseFirestore();
        final repository = FirestoreHomeRepository(firestore: firestore);

        expect(await repository.getCategories(), isEmpty);
      });

      test('maps kind onto CategoryModel.kind, so a category with no photo '
          'yet can still show a themed fallback image instead of a bare '
          'placeholder (see CategoryTile._fallbackAssetFor)', () async {
        final firestore = FakeFirebaseFirestore();
        await seedCategory(
          firestore,
          'lighting',
          name: 'Lighting',
          isActive: true,
          sortOrder: 10,
          kind: 'lighting',
        );
        final repository = FirestoreHomeRepository(firestore: firestore);

        final categories = await repository.getCategories();

        expect(categories.single.kind, ProductCategory.lighting);
      });
    });
  });
}
