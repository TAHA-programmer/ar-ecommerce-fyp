import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';

void main() {
  group('CustomerShoppingState', () {
    test('toggleFavorite/isFavorite forward to FavoritesRepository', () async {
      final state = CustomerShoppingState(
        MockFavoritesRepository(),
        MockCartRepository(),
      );

      expect(state.isFavorite('p1'), isFalse);
      await state.toggleFavorite('p1');
      expect(state.isFavorite('p1'), isTrue);
      expect(state.favoriteProductIds, {'p1'});
    });

    test(
      'addToCart merges into CartRepository and cartCount reflects it',
      () async {
        final state = CustomerShoppingState(
          MockFavoritesRepository(),
          MockCartRepository(),
        );

        await state.addToCart('p1', quantity: 2);
        expect(state.cartCount, 2);
        await state.addToCart('p1', quantity: 3);
        expect(state.cartCount, 5);
        expect(state.cartItems.length, 1);
      },
    );

    test('updateQuantity/removeFromCart translate CartItemModel.id back to '
        'the (productId, color, size) tuple the repository expects', () async {
      final cartRepository = MockCartRepository();
      final state = CustomerShoppingState(
        MockFavoritesRepository(),
        cartRepository,
      );

      await state.addToCart(
        'p1',
        quantity: 1,
        selectedColor: ProductColorOption.blue,
      );
      final cartItemId = state.cartItems.single.id;

      await state.updateQuantity(cartItemId, 4);
      expect(state.cartItems.single.quantity, 4);

      await state.removeFromCart(cartItemId);
      expect(state.cartItems, isEmpty);
    });

    test('updateQuantity/removeFromCart for an unknown cartItemId is a '
        'harmless no-op', () async {
      final state = CustomerShoppingState(
        MockFavoritesRepository(),
        MockCartRepository(),
      );
      expect(await state.updateQuantity('does-not-exist', 5), isNull);
      expect(await state.removeFromCart('does-not-exist'), isNull);
    });

    test('clearCart empties the cart', () async {
      final state = CustomerShoppingState(
        MockFavoritesRepository(),
        MockCartRepository(),
      );
      await state.addToCart('p1');
      await state.addToCart('p2');
      await state.clearCart();
      expect(state.cartItems, isEmpty);
      expect(state.cartCount, 0);
    });

    test('a repository failure returns a clean error message, never a raw '
        'exception', () async {
      final cartRepository = MockCartRepository()
        ..failAddItemWith = StateError('You are not signed in.');
      final state = CustomerShoppingState(
        MockFavoritesRepository(),
        cartRepository,
      );

      final error = await state.addToCart('p1');
      expect(error, 'You are not signed in.');
      expect(state.cartItems, isEmpty);
    });
  });
}
