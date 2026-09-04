import 'cart_item_model.dart';
import '../../product_details/models/product_detail_model.dart';

class PopulatedCartItem {
  final CartItemModel cartItem;
  final ProductDetailModel product;

  PopulatedCartItem(this.cartItem, this.product);
}
