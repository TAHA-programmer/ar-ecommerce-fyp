import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/product/product_mappers.dart';
import '../../../../core/models/product/product_publication_status.dart';
import '../../explore/models/catalog_product_model.dart';
import 'explore_repository.dart';

class MockExploreRepository implements ExploreRepository {
  final CommerceDatabase _db;

  MockExploreRepository(this._db);

  @override
  Future<List<CatalogProductModel>> getCatalog() async {
    // Simulate network delay
    await Future.delayed(const Duration(milliseconds: 800));

    // The complete customer-eligible catalogue: every published + active
    // product. `showInCatalog` is no longer a customer Explore filter
    // (Phase 9.3 pre-work — developer decision); it stays on the model but
    // does not gate visibility here. Mirrors `FirestoreExploreRepository`.
    return _db.products
        .where(
          (p) =>
              p.isActive &&
              p.publicationStatus == ProductPublicationStatus.published,
        )
        .map((p) => p.toCatalogModel())
        .toList();
  }

  @override
  Future<void> refresh() async {
    await Future.delayed(const Duration(milliseconds: 800));
  }
}
