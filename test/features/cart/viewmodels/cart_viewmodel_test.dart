import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_size.dart';
import 'package:twin_ar/features/cart/viewmodels/cart_viewmodel.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

void main() {
  late MockCommerceDatabase db;
  late CartViewModel viewModel;
  late CustomerShoppingState shoppingState;
  late MockProductDetailsRepository repository;

  setUp(() {
    shoppingState = CustomerShoppingState(
      MockFavoritesRepository(),
      MockCartRepository(),
    );
    db = MockCommerceDatabase();
    repository = MockProductDetailsRepository(db, simulateDelay: false);
    viewModel = CartViewModel(shoppingState, repository);
  });

  group('CartViewModel Tests', () {
    test('initializes correctly with empty cart', () {
      expect(viewModel.populatedItems.isEmpty, true);
      expect(viewModel.subtotal, 0.0);
      expect(viewModel.total, 0.0);
    });

    test('updates cart when shopping state changes', () async {
      shoppingState.addToCart('mens-oxford-shirt');
      await Future.delayed(
        const Duration(milliseconds: 800),
      ); // wait for async load
      expect(viewModel.populatedItems.length, 1);
    });

    test('one unresolvable cart product (deleted/unpublished) does not '
        'crash or block the rest of the cart - it is isolated into '
        'unavailableItems instead, never silently auto-removed', () async {
      shoppingState.addToCart('mens-oxford-shirt'); // resolvable
      shoppingState.addToCart('does-not-exist'); // unresolvable
      await Future.delayed(const Duration(milliseconds: 800));

      expect(viewModel.populatedItems.length, 1);
      expect(
        viewModel.populatedItems.first.cartItem.productId,
        'mens-oxford-shirt',
      );
      expect(viewModel.hasUnavailableItems, isTrue);
      expect(viewModel.unavailableItems.single.productId, 'does-not-exist');
      // Still present in the underlying cart - never auto-deleted on a
      // possibly-transient lookup failure.
      expect(
        shoppingState.cartItems.any((i) => i.productId == 'does-not-exist'),
        isTrue,
      );
    });

    group('Phase 8.11a - pre-checkout stock validation', () {
      test('validateForCheckout returns null and does not block when every '
          'line is available and within stock', () async {
        await db.updateStock('mens-oxford-shirt', 10);
        await shoppingState.addToCart('mens-oxford-shirt', quantity: 2);
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await viewModel.validateForCheckout(), isNull);
        expect(viewModel.hasStockIssues, isFalse);
      });

      test('validateForCheckout blocks (toast message) and marks the line '
          'when a product is out of stock; the item is NOT removed', () async {
        await db.updateStock('mens-oxford-shirt', 0);
        await shoppingState.addToCart('mens-oxford-shirt', quantity: 1);
        await Future.delayed(const Duration(milliseconds: 50));

        final message = await viewModel.validateForCheckout();
        expect(message, isNotNull);
        expect(viewModel.hasStockIssues, isTrue);
        final line = shoppingState.cartItems.single;
        expect(viewModel.stockIssueFor(line.id), 'Out of stock');
        expect(shoppingState.cartItems, isNotEmpty);
      });

      test('validateForCheckout aggregates quantity across different variants '
          'of the SAME productId - 3 + 3 vs stock 5 is blocked and both lines '
          'are flagged', () async {
        await db.updateStock('mens-oxford-shirt', 5);
        await shoppingState.addToCart(
          'mens-oxford-shirt',
          quantity: 3,
          selectedColor: ProductColorOption.black,
        );
        await shoppingState.addToCart(
          'mens-oxford-shirt',
          quantity: 3,
          selectedSize: ProductSize.m,
        );
        await Future.delayed(const Duration(milliseconds: 50));
        expect(viewModel.populatedItems.length, 2);

        final message = await viewModel.validateForCheckout();
        expect(message, isNotNull);
        for (final line in shoppingState.cartItems) {
          expect(viewModel.stockIssueFor(line.id), 'Only 5 available');
        }
      });

      test('validateForCheckout allows aggregated variants that fit (3 + 2 vs '
          'stock 5)', () async {
        await db.updateStock('mens-oxford-shirt', 5);
        await shoppingState.addToCart(
          'mens-oxford-shirt',
          quantity: 3,
          selectedColor: ProductColorOption.black,
        );
        await shoppingState.addToCart(
          'mens-oxford-shirt',
          quantity: 2,
          selectedSize: ProductSize.m,
        );
        await Future.delayed(const Duration(milliseconds: 50));

        expect(await viewModel.validateForCheckout(), isNull);
        expect(viewModel.hasStockIssues, isFalse);
      });

      test('validateForCheckout blocks when a line is unresolvable, and never '
          'auto-removes it', () async {
        await shoppingState.addToCart('mens-oxford-shirt');
        await shoppingState.addToCart('does-not-exist');
        await Future.delayed(const Duration(milliseconds: 50));

        final message = await viewModel.validateForCheckout();
        expect(message, contains('no longer available'));
        expect(viewModel.hasUnavailableItems, isTrue);
        expect(
          shoppingState.cartItems.any((i) => i.productId == 'does-not-exist'),
          isTrue,
        );
      });
    });
  });
}
