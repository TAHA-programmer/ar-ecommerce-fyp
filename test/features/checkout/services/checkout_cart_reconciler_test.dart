import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_size.dart';
import 'package:twin_ar/features/cart/models/cart_item_model.dart';
import 'package:twin_ar/features/checkout/models/checkout_payment_models.dart';
import 'package:twin_ar/features/checkout/services/checkout_cart_reconciler.dart';
import 'package:twin_ar/features/checkout/services/checkout_payment_service.dart';

class _FakeService implements CheckoutPaymentService {
  @override
  bool isConfigured = true;

  List<PurchasedLine> lines = const [];
  final List<String> calls = [];

  @override
  Future<List<PurchasedLine>> recentlyPurchasedLines(String uid) async {
    calls.add(uid);
    return lines;
  }

  @override
  Future<CreatePaymentIntentResult> createPaymentIntent({
    required List<CheckoutLineItemRequest> items,
    required String addressId,
    required String idempotencyKey,
  }) => throw UnimplementedError();

  @override
  Future<void> presentPaymentSheet({required String clientSecret}) =>
      throw UnimplementedError();

  @override
  Stream<CheckoutSessionUpdate> watchSession(String sessionId) =>
      const Stream.empty();
}

CartItemModel _item(
  String productId, {
  int quantity = 1,
  ProductColorOption? color,
  ProductSize? size,
}) => CartItemModel(
  productId: productId,
  quantity: quantity,
  selectedColor: color,
  selectedSize: size,
);

AuthSessionState _signedIn() => AuthSessionState()
  ..setSession(
    AuthResult.success(
      userId: 'u1',
      email: 'u1@x.com',
      role: UserRole.customer,
    ),
  );

void main() {
  // CheckoutCartReconciler registers a WidgetsBindingObserver.
  TestWidgetsFlutterBinding.ensureInitialized();

  late MockCartRepository cart;
  late CustomerShoppingState shopping;

  setUp(() {
    cart = MockCartRepository();
    shopping = CustomerShoppingState(MockFavoritesRepository(), cart);
  });

  group('removePurchasedLinesFromCart', () {
    test(
      'removes an exact-match line when cart qty == purchased qty',
      () async {
        cart.debugSetItems([_item('shirt', quantity: 2)]);
        await removePurchasedLinesFromCart(shopping, const [
          PurchasedLine(productId: 'shirt', quantity: 2),
        ]);
        expect(shopping.cartItems, isEmpty);
      },
    );

    test(
      'reduces the line when the cart has MORE than was purchased',
      () async {
        cart.debugSetItems([_item('shirt', quantity: 5)]);
        await removePurchasedLinesFromCart(shopping, const [
          PurchasedLine(productId: 'shirt', quantity: 2),
        ]);
        expect(shopping.cartItems.single.quantity, 3);
      },
    );

    test(
      'removes the line when the cart has FEWER than was purchased',
      () async {
        cart.debugSetItems([_item('shirt', quantity: 1)]);
        await removePurchasedLinesFromCart(shopping, const [
          PurchasedLine(productId: 'shirt', quantity: 2),
        ]);
        expect(shopping.cartItems, isEmpty);
      },
    );

    test('never touches a line for a DIFFERENT product', () async {
      cart.debugSetItems([
        _item('shirt', quantity: 2),
        _item('lamp', quantity: 1),
      ]);
      await removePurchasedLinesFromCart(shopping, const [
        PurchasedLine(productId: 'shirt', quantity: 2),
      ]);
      expect(shopping.cartItems.map((c) => c.productId), ['lamp']);
    });

    test(
      'never touches a line for the same product but a different variant',
      () async {
        final black = ProductColorOption.values.first;
        final other = ProductColorOption.values.length > 1
            ? ProductColorOption.values[1]
            : ProductColorOption.values.first;
        // Only meaningful when at least two colour options exist.
        if (black == other) return;
        cart.debugSetItems([
          _item('shirt', quantity: 1, color: black),
          _item('shirt', quantity: 1, color: other),
        ]);
        await removePurchasedLinesFromCart(shopping, [
          PurchasedLine(
            productId: 'shirt',
            quantity: 1,
            selectedColor: black.name,
          ),
        ]);
        expect(shopping.cartItems.single.selectedColor, other);
      },
    );

    test('is a no-op when the purchased line is not in the cart', () async {
      cart.debugSetItems([_item('lamp', quantity: 1)]);
      await removePurchasedLinesFromCart(shopping, const [
        PurchasedLine(productId: 'shirt', quantity: 1),
      ]);
      expect(shopping.cartItems.single.productId, 'lamp');
    });

    test('skips invalid purchased lines (blank id / zero qty)', () async {
      cart.debugSetItems([_item('shirt', quantity: 1)]);
      await removePurchasedLinesFromCart(shopping, const [
        PurchasedLine(productId: '', quantity: 3),
        PurchasedLine(productId: 'shirt', quantity: 0),
      ]);
      expect(shopping.cartItems.single.productId, 'shirt');
    });
  });

  group('CheckoutCartReconciler', () {
    test('reconcileNow clears purchased lines for a signed-in user', () async {
      cart.debugSetItems([
        _item('shirt', quantity: 2),
        _item('lamp', quantity: 1),
      ]);
      final service = _FakeService()
        ..lines = const [PurchasedLine(productId: 'shirt', quantity: 2)];
      final reconciler = CheckoutCartReconciler(service, shopping, _signedIn());
      addTearDown(reconciler.dispose);

      await reconciler.reconcileNow();

      expect(service.calls, ['u1']);
      expect(shopping.cartItems.map((c) => c.productId), ['lamp']);
    });

    test('does nothing when the payment service is not configured', () async {
      cart.debugSetItems([_item('shirt', quantity: 1)]);
      final service = _FakeService()
        ..isConfigured = false
        ..lines = const [PurchasedLine(productId: 'shirt', quantity: 1)];
      final reconciler = CheckoutCartReconciler(service, shopping, _signedIn());
      addTearDown(reconciler.dispose);

      await reconciler.reconcileNow();

      expect(service.calls, isEmpty);
      expect(shopping.cartItems, hasLength(1));
    });

    test('does nothing when signed out', () async {
      cart.debugSetItems([_item('shirt', quantity: 1)]);
      final service = _FakeService()
        ..lines = const [PurchasedLine(productId: 'shirt', quantity: 1)];
      final reconciler = CheckoutCartReconciler(
        service,
        shopping,
        AuthSessionState(),
      );
      addTearDown(reconciler.dispose);

      await reconciler.reconcileNow();

      expect(service.calls, isEmpty);
      expect(shopping.cartItems, hasLength(1));
    });

    test('runs automatically when the user signs in', () async {
      cart.debugSetItems([_item('shirt', quantity: 1)]);
      final auth = AuthSessionState();
      final service = _FakeService()
        ..lines = const [PurchasedLine(productId: 'shirt', quantity: 1)];
      final reconciler = CheckoutCartReconciler(service, shopping, auth);
      addTearDown(reconciler.dispose);

      auth.setSession(
        AuthResult.success(
          userId: 'u1',
          email: 'u1@x.com',
          role: UserRole.customer,
        ),
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(service.calls, contains('u1'));
      expect(shopping.cartItems, isEmpty);
    });
  });
}
