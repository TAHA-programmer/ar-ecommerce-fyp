import '../models/product_detail_model.dart';

abstract class ProductDetailsRepository {
  Future<ProductDetailModel> getProductDetails(String productId);
}
