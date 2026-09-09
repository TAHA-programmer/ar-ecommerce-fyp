import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/category_firestore_mapper.dart';
import '../data/home_static_content.dart';
import '../models/category_model.dart';
import '../models/home_banner_model.dart';
import 'home_repository.dart';

/// Firestore-backed [HomeRepository]: the static hero banners and the real
/// Admin-managed `categories` collection.
///
/// Home's **product** sections do not come through here — [HomeViewModel]
/// derives them from the live `CommerceDatabase` catalogue cache plus the
/// `productStats` / `users/{uid}/recentlyViewed` ordering signals (Dynamic
/// Home Content Stage 3). This class is deliberately tiny as a result.
class FirestoreHomeRepository implements HomeRepository {
  final FirebaseFirestore _firestore;

  FirestoreHomeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  @override
  Future<List<HomeBannerModel>> getBanners() async => homeStaticBanners;

  /// Real Admin-managed categories (Phase 8.8b). Mirrors
  /// `FirestoreCategoryRepository`'s customer-role query shape exactly — a
  /// single-field `isActive == true` filter with NO server-side `orderBy`
  /// (so no composite index is needed), sorted client-side by `sortOrder`.
  /// Reuses the canonical `categoryModelFromFirestore` mapper. One-shot
  /// `Future` read (not a listener) to match `loadHomeData()`/`refresh()`'s
  /// batch re-fetch model.
  @override
  Future<List<CategoryModel>> getCategories() async {
    final snapshot = await _firestore
        .collection('categories')
        .where('isActive', isEqualTo: true)
        .get();
    final categories =
        snapshot.docs
            .map((d) => categoryModelFromFirestore(d.id, d.data()))
            .toList()
          ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return categories
        .map(
          (c) => CategoryModel(
            id: c.categoryId,
            name: c.name,
            imageUrl: c.imageUrl,
            kind: c.kind,
          ),
        )
        .toList();
  }

  @override
  Future<void> refresh() async {}
}
