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
    test('getCatalog enforces the strict triple: published + active + '
        'showInCatalog - a Home-curated (showInCatalog:false) product must '
        'never leak into Explore', () async {
      final firestore = FakeFirebaseFirestore();
      await _seed(firestore, 'catalog-visible');
      await _seed(firestore, 'home-only-curated', showInCatalog: false);
      await _seed(firestore, 'draft-product', publicationStatus: 'draft');
      await _seed(firestore, 'inactive-product', isActive: false);
      final repository = FirestoreExploreRepository(firestore: firestore);

      final result = await repository.getCatalog();

      expect(result.map((p) => p.summary.id).toList(), ['catalog-visible']);
    });
  });
}
