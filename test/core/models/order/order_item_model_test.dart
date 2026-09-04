import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/order/order_item_model.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';

void main() {
  group('OrderItemModel - Phase 8.7 source-awareness', () {
    test('imageSource defaults to .asset for pre-8.7 construction sites', () {
      final item = OrderItemModel(
        productId: 'p1',
        productName: 'Test',
        imagePath: 'assets/test.png',
        quantity: 1,
        unitPrice: 100,
        lineTotal: 100,
      );

      expect(item.imageSource, ProductImageSource.asset);
      expect(item.image.source, ProductImageSource.asset);
      expect(item.image.path, 'assets/test.png');
    });

    test('a network-sourced snapshot preserves .network through .image', () {
      final item = OrderItemModel(
        productId: 'p1',
        productName: 'Test',
        imagePath: 'https://firebasestorage.example/a.jpg',
        imageSource: ProductImageSource.network,
        quantity: 1,
        unitPrice: 100,
        lineTotal: 100,
      );

      expect(item.image.source, ProductImageSource.network);
      expect(item.image.path, 'https://firebasestorage.example/a.jpg');
    });
  });
}
