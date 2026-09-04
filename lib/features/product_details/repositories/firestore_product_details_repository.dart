import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/product_firestore_mapper.dart';
import '../../../core/models/product/product_mappers.dart';
import '../models/product_detail_model.dart';
import 'product_details_repository.dart';

/// Phase 8.5: real Firestore-backed product reads for Product Details.
///
/// A single-document `.get()` by known ID - unlike a collection query, this
/// only needs to satisfy `firestore.rules` for *that one document*, so no
/// role-awareness is needed here. A missing document, a permission-denied
/// (e.g. a stale/shared link to a draft product a customer can't read), or
/// any other failure all map to the same [StateError] [ProductDetailModel]
/// callers already expect from [MockProductDetailsRepository] -
/// `ProductDetailsViewModel._loadProduct()` already catches generically, so
/// no view-layer changes are needed.
class FirestoreProductDetailsRepository implements ProductDetailsRepository {
  final FirebaseFirestore _firestore;

  FirestoreProductDetailsRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<ProductDetailModel> getProductDetails(String productId) async {
    try {
      final snapshot = await _firestore
          .collection('products')
          .doc(productId)
          .get();
      final data = snapshot.data();
      if (data == null) {
        throw StateError('Product not found for ID: $productId');
      }
      return productModelFromFirestore(snapshot.id, data).toDetailModel();
    } on StateError {
      rethrow;
    } catch (_) {
      throw StateError('Product not found for ID: $productId');
    }
  }
}
