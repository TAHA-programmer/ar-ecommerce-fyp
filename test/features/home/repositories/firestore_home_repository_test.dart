import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/features/home/repositories/firestore_home_repository.dart';

void main() {
  group('FirestoreHomeRepository', () {
    // Dynamic Home Content Stage 3: the curated-ID / `recommendationRank`
    // product methods were removed — Home derives every product section from
    // the CommerceDatabase catalogue cache now. Only banners + the real
    // categories collection come through this repository.

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
