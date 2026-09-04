import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/product_details/repositories/firestore_product_details_repository.dart';

void main() {
  group('FirestoreProductDetailsRepository', () {
    test(
      'getProductDetails maps an existing document to a ProductDetailModel',
      () async {
        final firestore = FakeFirebaseFirestore();
        await firestore.collection('products').doc('p1').set({
          'sku': 'SKU-1',
          'title': 'Luna Accent Chair',
          'description': 'A nice chair',
          'category': 'furniture',
          'subcategory': 'Accent Chairs',
          'priceAmount': 12000,
          'stockQuantity': 10,
          'isActive': true,
          'showInCatalog': true,
          'publicationStatus': 'published',
          'mainImage': {
            'path': 'assets/x.png',
            'source': 'asset',
            'altText': '',
          },
          'galleryMedia': <Map<String, dynamic>>[],
          'experienceType': 'roomAr',
          'availableColors': <String>[],
          'availableSizes': <String>[],
          'specifications': <Map<String, dynamic>>[],
          'deliveryEstimate': '3-5 days',
          'recommendationRank': 0,
          'popularityScore': 0,
          'addedDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
          'rating': 4.8,
          'reviewCount': 124,
        });
        final repository = FirestoreProductDetailsRepository(
          firestore: firestore,
        );

        final result = await repository.getProductDetails('p1');

        expect(result.summary.id, 'p1');
        expect(result.summary.title, 'Luna Accent Chair');
        expect(result.subcategory, 'Accent Chairs');
      },
    );

    test('getProductDetails throws for a missing document', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirestoreProductDetailsRepository(
        firestore: firestore,
      );

      expect(
        () => repository.getProductDetails('does-not-exist'),
        throwsStateError,
      );
    });
  });
}
