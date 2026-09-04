import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/data/product_firestore_mapper.dart';
import '../../../../core/models/product/product_mappers.dart';
import '../../explore/models/catalog_product_model.dart';
import 'explore_repository.dart';

/// Phase 8.5: real Firestore-backed product reads for the Explore catalog.
///
/// `showInCatalog == true` is applied as a query-level filter here (not a
/// security rule - see Correction 5 / `firestore.rules`), exactly matching
/// [MockExploreRepository]'s existing strict triple condition:
/// `publicationStatus == published && isActive == true && showInCatalog ==
/// true`. This is deliberately a *narrower* query than the rule allows
/// (which only requires `published && isActive`), so it always satisfies
/// the rule automatically.
class FirestoreExploreRepository implements ExploreRepository {
  final FirebaseFirestore _firestore;

  FirestoreExploreRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<CatalogProductModel>> getCatalog() async {
    final snapshot = await _firestore
        .collection('products')
        .where('publicationStatus', isEqualTo: 'published')
        .where('isActive', isEqualTo: true)
        .where('showInCatalog', isEqualTo: true)
        .get();

    return snapshot.docs
        .map((d) => productModelFromFirestore(d.id, d.data()).toCatalogModel())
        .toList();
  }

  @override
  Future<void> refresh() async {}
}
