import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/cart_repository.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_size.dart';

void main() {
  group('MockCartRepository', () {
    test('addItem for a new product/variant creates a new line', () async {
      final repo = MockCartRepository();
      await repo.addItem(productId: 'p1', quantity: 2);
      expect(repo.items.single.productId, 'p1');
      expect(repo.items.single.quantity, 2);
    });

    test('addItem for the same product/variant merges (sums) quantity '
        'instead of creating a second line', () async {
      final repo = MockCartRepository();
      await repo.addItem(
        productId: 'p1',
        quantity: 2,
        selectedColor: ProductColorOption.blue,
        selectedSize: ProductSize.m,
      );
      await repo.addItem(
        productId: 'p1',
        quantity: 3,
        selectedColor: ProductColorOption.blue,
        selectedSize: ProductSize.m,
      );
      expect(repo.items.length, 1);
      expect(repo.items.single.quantity, 5);
    });

    test(
      'a different variant of the same product creates a separate line',
      () async {
        final repo = MockCartRepository();
        await repo.addItem(
          productId: 'p1',
          quantity: 1,
          selectedColor: ProductColorOption.blue,
        );
        await repo.addItem(
          productId: 'p1',
          quantity: 1,
          selectedColor: ProductColorOption.black,
        );
        expect(repo.items.length, 2);
      },
    );

    test(
      'quantity is clamped to cartMaxQuantity on both add and merge',
      () async {
        final repo = MockCartRepository();
        await repo.addItem(productId: 'p1', quantity: 90);
        await repo.addItem(productId: 'p1', quantity: 90);
        expect(repo.items.single.quantity, cartMaxQuantity);
      },
    );

    test(
      'setQuantity sets an absolute quantity, clamped to the bounds',
      () async {
        final repo = MockCartRepository();
        await repo.addItem(productId: 'p1', quantity: 1);
        await repo.setQuantity(productId: 'p1', quantity: 500);
        expect(repo.items.single.quantity, cartMaxQuantity);

        await repo.setQuantity(productId: 'p1', quantity: 0);
        // 0 is below cartMinQuantity - a no-op, never a removal.
        expect(repo.items.single.quantity, cartMaxQuantity);
      },
    );

    test('removeItem removes exactly the matching line', () async {
      final repo = MockCartRepository();
      await repo.addItem(
        productId: 'p1',
        selectedColor: ProductColorOption.blue,
      );
      await repo.addItem(
        productId: 'p1',
        selectedColor: ProductColorOption.black,
      );
      await repo.removeItem(
        productId: 'p1',
        selectedColor: ProductColorOption.blue,
      );
      expect(repo.items.length, 1);
      expect(repo.items.single.selectedColor, ProductColorOption.black);
    });

    test('clear empties the cart', () async {
      final repo = MockCartRepository();
      await repo.addItem(productId: 'p1');
      await repo.addItem(productId: 'p2');
      await repo.clear();
      expect(repo.items, isEmpty);
    });

    test('itemCount sums quantities across all lines', () async {
      final repo = MockCartRepository();
      await repo.addItem(productId: 'p1', quantity: 2);
      await repo.addItem(productId: 'p2', quantity: 3);
      expect(repo.itemCount, 5);
    });

    test('failAddItemWith causes addItem to throw cleanly', () async {
      final repo = MockCartRepository()..failAddItemWith = StateError('boom');
      await expectLater(
        repo.addItem(productId: 'p1'),
        throwsA(isA<StateError>()),
      );
    });
  });
}
