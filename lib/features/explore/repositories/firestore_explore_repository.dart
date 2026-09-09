import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/data/product_firestore_mapper.dart';
import '../../../../core/models/product/product_mappers.dart';
import '../../explore/models/catalog_product_model.dart';
import 'explore_repository.dart';

/// Phase 8.5: real Firestore-backed product reads for the Explore catalog.
///
/// The customer catalogue is every `publicationStatus == 'published' &&
/// isActive == true` product — the exact set `firestore.rules`' `products/{id}`
/// read rule allows a signed-in customer, so the query satisfies the rule
/// automatically and no draft/inactive product is ever reachable.
///
/// Phase 9.3 pre-work: the earlier extra `showInCatalog == true` clause was
/// removed by developer decision — Explore now shows the complete
/// customer-eligible catalogue, not a curated subset. `showInCatalog` remains
/// on the model/Admin form but no longer gates customer Explore visibility.
/// Home keeps its own independent curation (it never used `showInCatalog` as a
/// filter either — see `FirestoreHomeRepository`).
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
        .get();

    return snapshot.docs
        .map((d) => productModelFromFirestore(d.id, d.data()).toCatalogModel())
        .toList();
  }

  @override
  Future<void> refresh() async {}
}
