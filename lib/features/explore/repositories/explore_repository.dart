import '../models/catalog_product_model.dart';

abstract class ExploreRepository {
  Future<List<CatalogProductModel>> getCatalog();
  Future<void> refresh();
}
