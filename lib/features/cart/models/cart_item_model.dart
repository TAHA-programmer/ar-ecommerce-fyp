import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';

class CartItemModel {
  final String productId;
  final int quantity;
  final ProductColorOption? selectedColor;
  final ProductSize? selectedSize;

  CartItemModel({
    required this.productId,
    this.quantity = 1,
    this.selectedColor,
    this.selectedSize,
  });

  String get id {
    final colorStr = selectedColor?.name ?? 'defaultColor';
    final sizeStr = selectedSize?.name ?? 'defaultSize';
    return '${productId}_${colorStr}_$sizeStr';
  }

  CartItemModel copyWith({int? quantity}) {
    return CartItemModel(
      productId: productId,
      quantity: quantity ?? this.quantity,
      selectedColor: selectedColor,
      selectedSize: selectedSize,
    );
  }
}
