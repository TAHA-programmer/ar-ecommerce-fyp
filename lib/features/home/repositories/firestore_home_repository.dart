import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../core/data/category_firestore_mapper.dart';
import '../../../core/data/product_firestore_mapper.dart';
import '../../../core/models/product/product_mappers.dart';
import '../../../core/models/product/product_summary_model.dart';
import '../data/home_static_content.dart';
import '../models/category_model.dart';
import '../models/home_banner_model.dart';
import 'home_repository.dart';

/// Phase 8.5: real Firestore-backed product reads for Home's curated
/// sections. Queries Firestore directly (not through [CommerceDatabase]) -
/// each section is a one-shot `Future`, matching [HomeRepository]'s
/// existing shape, so no live-listener/role-awareness is needed here (that
/// complexity is isolated to `FirestoreCommerceDatabase`, which only Admin
/// and Checkout actually need).
///
/// Every section's filter is a direct port of [MockHomeRepository]'s exact
/// existing logic - same curated ID lists, same `recommendationRank`
/// sentinels - translated into real `.where()` clauses instead of in-memory
/// filtering, so Home's curation is byte-for-byte unchanged this phase (see
/// `14_AGENT_HANDOFF_RULES.md` section F: "Home has its OWN visibility
/// logic - do NOT apply Explore rules to Home"). `published && isActive` is
/// applied everywhere as defense-in-depth, matching the Firestore rule.
class FirestoreHomeRepository implements HomeRepository {
  final FirebaseFirestore _firestore;

  FirestoreHomeRepository({FirebaseFirestore? firestore})
    : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _products =>
      _firestore.collection('products');

  Query<Map<String, dynamic>> get _publishedActive => _products
      .where('publicationStatus', isEqualTo: 'published')
      .where('isActive', isEqualTo: true);

  /// Fetches a curated ID list as individual `products/{id}` document reads,
  /// run in parallel, order-preserving.
  ///
  /// It deliberately does NOT use a single
  /// `.where(FieldPath.documentId, whereIn: ids)` query: `firestore.rules`'
  /// `products/{id}` read rule dereferences `resource.data.publicationStatus`,
  /// and Firestore evaluates that rule per requested id for a
  /// `whereIn`-on-documentId query. A curated id that has since been deleted,
  /// unpublished or deactivated (e.g. `minimalist-bedroom-set`, permanently
  /// removed from the catalogue) makes `resource` null for that id, the rule
  /// throws, and the ENTIRE query is rejected with `permission-denied` —
  /// which took all of Home down, not just one rail. Per-document `get()`s
  /// isolate that: a missing / draft / inactive id simply fails its own
  /// read (the rule denies it) and is skipped, never the whole batch.
  Future<List<ProductSummaryModel>> _fetchByIds(List<String> ids) async {
    if (ids.isEmpty) return const [];
    final snapshots = await Future.wait(
      ids.map(
        (id) => _products
            .doc(id)
            .get()
            .then<DocumentSnapshot<Map<String, dynamic>>?>(
              (d) => d,
              // Deleted id -> `not-found`; draft/inactive id -> the rule
              // denies it (`permission-denied`). Either way: skip it.
              onError: (_) => null,
            ),
      ),
    );
    final out = <ProductSummaryModel>[];
    for (final doc in snapshots) {
      if (doc == null || !doc.exists) continue;
      final data = doc.data();
      if (data == null) continue;
      // Defence in depth: the rule already guarantees published + active, but
      // a curated rail must never surface a draft even if that rule is later
      // relaxed.
      if (data['publicationStatus'] != 'published' ||
          data['isActive'] != true) {
        continue;
      }
      out.add(productModelFromFirestore(doc.id, data).toSummaryModel());
    }
    return out;
  }

  Future<List<ProductSummaryModel>> _fetchByField(
    String field,
    Object value,
  ) async {
    final snapshot = await _publishedActive
        .where(field, isEqualTo: value)
        .get();
    return snapshot.docs
        .map((d) => productModelFromFirestore(d.id, d.data()).toSummaryModel())
        .toList();
  }

  @override
  Future<List<HomeBannerModel>> getBanners() async => homeStaticBanners;

  /// Real Admin-managed categories (Phase 8.8b), replacing the static
  /// curated list. Deliberately mirrors `FirestoreCategoryRepository`'s own
  /// customer-role query shape exactly - a single-field `isActive == true`
  /// filter with NO server-side `orderBy` (avoids requiring a composite
  /// index for a query this small-scale app doesn't need), sorted
  /// client-side by `sortOrder` instead. Reuses the canonical
  /// `categoryModelFromFirestore` mapper so this file never hand-rolls its
  /// own copy of the `categories/{id}` schema parsing. This is a one-shot
  /// `Future` read (not a live listener) to match every other method on
  /// this class - Home's `loadHomeData()`/`refresh()` already re-fetch
  /// everything as a batch, so a listener isn't needed here.
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
  Future<List<ProductSummaryModel>> getBestSellers() => _fetchByIds(const [
    'luna-3-seater-sofa',
    'boho-woven-rug',
    'classic-blue-shirt',
  ]);

  @override
  Future<List<ProductSummaryModel>> getFeaturedProducts() =>
      _fetchByField('recommendationRank', 10);

  @override
  Future<List<ProductSummaryModel>> getNewArrivals() =>
      _fetchByField('recommendationRank', 20);

  // `minimalist-bedroom-set` was permanently removed from the catalogue
  // (reference pack §33.5) and is intentionally not listed here. `_fetchByIds`
  // now tolerates a missing id, but a permanently-dead literal is still dead
  // weight — a replacement AR product is a curation decision for later.
  @override
  Future<List<ProductSummaryModel>> getArEnabledProducts() => _fetchByIds(
    const ['wooden-console', 'glass-coffee-table', 'velvet-armchair'],
  );

  @override
  Future<List<ProductSummaryModel>> getVirtualTryOnCollection() =>
      _fetchByIds(const [
        'floral-summer-dress',
        'casual-hoodie',
        'classic-blue-shirt',
        'autumn-outfit',
      ]);

  @override
  Future<List<ProductSummaryModel>> getPopularFurniture() => _fetchByIds(const [
    'marble-side-table',
    'velvet-armchair',
    'boho-woven-rug',
    'ceramic-vases-set',
  ]);

  @override
  Future<List<ProductSummaryModel>> getRecentlyViewed() => _fetchByIds(const [
    'velvet-armchair',
    'ceramic-vases-set',
    'classic-blue-shirt',
    'autumn-outfit',
  ]);

  @override
  Future<void> refresh() async {}
}
