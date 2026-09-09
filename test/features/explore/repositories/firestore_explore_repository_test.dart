import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/explore/repositories/firestore_explore_repository.dart';

Future<void> _seed(
  FakeFirebaseFirestore firestore,
  String id, {
  String publicationStatus = 'published',
  bool isActive = true,
  bool showInCatalog = true,
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
    'showInCatalog': showInCatalog,
    'publicationStatus': publicationStatus,
    'mainImage': {'path': 'assets/x.png', 'source': 'asset', 'altText': ''},
    'galleryMedia': <Map<String, dynamic>>[],
    'experienceType': 'none',
    'availableColors': <String>[],
    'availableSizes': <String>[],
    'specifications': <Map<String, dynamic>>[],
    'deliveryEstimate': '3-5 days',
    'recommendationRank': 0,
    'popularityScore': 0,
    'addedDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'rating': 4.5,
    'reviewCount': 10,
  });
}

void main() {
  group('FirestoreExploreRepository', () {
    test(
      'getCatalog returns every published + active product - '
      'Phase 9.3 pre-work: showInCatalog no longer gates customer Explore '
      'visibility, so a showInCatalog:false product IS in the catalogue now',
      () async {
        final firestore = FakeFirebaseFirestore();
        await _seed(firestore, 'catalog-visible');
        await _seed(firestore, 'was-home-only', showInCatalog: false);
        await _seed(firestore, 'draft-product', publicationStatus: 'draft');
        await _seed(firestore, 'inactive-product', isActive: false);
        final repository = FirestoreExploreRepository(firestore: firestore);

        final result = await repository.getCatalog();

        expect(result.map((p) => p.summary.id).toSet(), {
          'catalog-visible',
          'was-home-only',
        });
      },
    );

    test('getCatalog still excludes drafts and inactive products', () async {
      final firestore = FakeFirebaseFirestore();
      await _seed(firestore, 'published-active');
      await _seed(firestore, 'draft', publicationStatus: 'draft');
      await _seed(firestore, 'inactive', isActive: false);
      await _seed(
        firestore,
        'draft-and-inactive',
        publicationStatus: 'draft',
        isActive: false,
      );
      final repository = FirestoreExploreRepository(firestore: firestore);

      final result = await repository.getCatalog();

      expect(result.map((p) => p.summary.id).toList(), ['published-active']);
    });

    test(
      'getCatalog has no arbitrary ceiling - all N published+active products '
      'are returned even past the old ~36 curated count',
      () async {
        final firestore = FakeFirebaseFirestore();
        for (var i = 0; i < 42; i++) {
          await _seed(
            firestore,
            'p-$i',
            // half of them were "Home-only" under the old rule
            showInCatalog: i.isEven,
          );
        }
        final repository = FirestoreExploreRepository(firestore: firestore);

        final result = await repository.getCatalog();

        expect(result.length, 42);
      },
    );
  });
}
