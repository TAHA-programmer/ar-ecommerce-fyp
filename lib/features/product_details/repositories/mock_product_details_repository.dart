import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/product/product_mappers.dart';
import '../models/product_detail_model.dart';
import 'product_details_repository.dart';

class MockProductDetailsRepository implements ProductDetailsRepository {
  final CommerceDatabase _db;
  final bool simulateDelay;

  MockProductDetailsRepository(this._db, {this.simulateDelay = true});

  @override
  Future<ProductDetailModel> getProductDetails(String productId) async {
    if (simulateDelay) {
      await Future.delayed(const Duration(milliseconds: 600));
    }

    try {
      final product = _db.getProductById(productId);
      return product.toDetailModel();
    } catch (e) {
      throw StateError('Product not found for ID: $productId');
    }
  }
}
