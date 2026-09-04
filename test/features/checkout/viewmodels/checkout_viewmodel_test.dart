import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/app/viewmodels/customer_address_state.dart';
import 'package:twin_ar/app/viewmodels/customer_order_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_address_repository.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/checkout/models/checkout_payment_models.dart';
import 'package:twin_ar/features/checkout/services/checkout_payment_service.dart';
import 'package:twin_ar/features/checkout/viewmodels/checkout_viewmodel.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

/// Fully controllable [CheckoutPaymentService] - no real Stripe or Firebase.
class _FakeCheckoutPaymentService implements CheckoutPaymentService {
  _FakeCheckoutPaymentService();

  @override
  bool isConfigured = true;

  set configured(bool v) => isConfigured = v;

  // createPaymentIntent
  final List<String> createCalls = [];
  CreatePaymentIntentResult Function(String idempotencyKey)? createResult;
  CheckoutPaymentException? createError;

  // presentPaymentSheet
  int presentCalls = 0;
  CheckoutPaymentException? presentError;
  final Completer<void> _presentGate = Completer<void>()..complete();

  // watchSession
  final Map<String, StreamController<CheckoutSessionUpdate>> _sessions = {};
  StreamController<CheckoutSessionUpdate> sessionController(String id) =>
      _sessions.putIfAbsent(
        id,
        () => StreamController<CheckoutSessionUpdate>.broadcast(),
      );

  @override
  Future<CreatePaymentIntentResult> createPaymentIntent({
    required List<CheckoutLineItemRequest> items,
    required String addressId,
    required String idempotencyKey,
  }) async {
    createCalls.add(idempotencyKey);
    if (createError != null) throw createError!;
    final builder = createResult ?? _defaultResult;
    return builder(idempotencyKey);
  }

  CreatePaymentIntentResult _defaultResult(String key) =>
      CreatePaymentIntentResult(
        checkoutSessionId: 'cs_$key',
        paymentIntentClientSecret: 'pi_${key}_secret',
        amountMinor: 750000,
        currency: 'pkr',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        totals: const CheckoutTotals(
          subtotal: 8000,
          deliveryFee: 500,
          discount: 1000,
          total: 7500,
        ),
      );

  @override
  Future<void> presentPaymentSheet({required String clientSecret}) async {
    presentCalls++;
    await _presentGate.future;
    if (presentError != null) throw presentError!;
  }

  @override
  Stream<CheckoutSessionUpdate> watchSession(String sessionId) =>
      sessionController(sessionId).stream;

  List<PurchasedLine> recentPurchased = const [];
  final List<String> recentlyPurchasedCalls = [];

  @override
  Future<List<PurchasedLine>> recentlyPurchasedLines(String uid) async {
    recentlyPurchasedCalls.add(uid);
    return recentPurchased;
  }

  String get lastCheckoutSessionId => 'cs_${createCalls.last}';
}

AddressDraft _draft({String fullName = 'Test User'}) => AddressDraft(
  label: 'Home',
  fullName: fullName,
  phoneNumber: '03001234567',
  addressLine1: '123 Test St',
  city: 'Karachi',
  provinceOrState: 'Sindh',
  postalCode: '74000',
);

OrderModel _order(String id, {String userId = 'test-uid'}) => OrderModel(
  id: id,
  userId: userId,
  paymentId: 'pay_$id',
  items: const [],
  orderDate: DateTime(2026, 1, 1),
  subtotal: 8000,
  deliveryFee: 500,
  discount: 1000,
  total: 7500,
  paymentMethod: PaymentMethod.stripeCard,
  paymentStatus: PaymentStatus.paid,
  orderStatus: OrderStatus.pending,
  deliveryAddress: AddressModel(
    id: 'embedded',
    fullName: 'Test User',
    phoneNumber: '03001234567',
    addressLine1: '123 Test St',
    city: 'Karachi',
    provinceOrState: 'Sindh',
    postalCode: '74000',
  ),
  estimatedDeliveryStart: DateTime(2026, 1, 8),
  estimatedDeliveryEnd: DateTime(2026, 1, 15),
);

void main() {
  late CustomerShoppingState shoppingState;
  late CustomerAddressState addressState;
  late CustomerOrderState orderState;
  late MockCommerceDatabase db;
  late MockProductDetailsRepository repository;
  late AuthSessionState authState;
  late _FakeCheckoutPaymentService service;

  CheckoutViewModel makeViewModel({
    Duration finalizeTimeout = const Duration(milliseconds: 150),
  }) => CheckoutViewModel(
    shoppingState,
    addressState,
    repository,
    authState,
    service,
    orderState,
    finalizeTimeout: finalizeTimeout,
  );

  Future<void> primeCart(CheckoutViewModel vm, {int qty = 2}) async {
    await addressState.addAddress(_draft());
    await shoppingState.addToCart('mens-oxford-shirt', quantity: qty);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expect(vm.isEmptyCart, isFalse);
    expect(vm.isMissingAddress, isFalse);
  }

  setUp(() {
    shoppingState = CustomerShoppingState(
      MockFavoritesRepository(),
      MockCartRepository(),
    );
    addressState = CustomerAddressState(MockAddressRepository());
    db = MockCommerceDatabase();
    orderState = CustomerOrderState(db);
    repository = MockProductDetailsRepository(db, simulateDelay: false);
    authState = AuthSessionState()
      ..setSession(
        AuthResult.success(
          userId: 'test-uid',
          email: 'test@twinar.com',
          role: UserRole.customer,
        ),
      );
    service = _FakeCheckoutPaymentService();
  });

  group('CheckoutViewModel - load & guards', () {
    test('initializes idle with empty cart and no address', () {
      final vm = makeViewModel();
      expect(vm.phase, CheckoutPhase.idle);
      expect(vm.populatedItems, isEmpty);
      expect(vm.isEmptyCart, isTrue);
      expect(vm.isMissingAddress, isTrue);
    });

    test(
      'missing publishable key -> paymentUnavailable, server never called',
      () async {
        service.configured = false;
        final vm = makeViewModel();
        expect(vm.phase, CheckoutPhase.paymentUnavailable);
        await primeCart(vm);
        await vm.startCheckout();
        expect(service.createCalls, isEmpty);
        expect(vm.phase, CheckoutPhase.paymentUnavailable);
        expect(vm.error, contains('unavailable'));
      },
    );

    test(
      'an unresolvable cart line surfaces an inline message and blocks pay',
      () async {
        final vm = makeViewModel();
        await addressState.addAddress(_draft());
        await shoppingState.addToCart('mens-oxford-shirt', quantity: 1);
        await shoppingState.addToCart('does-not-exist', quantity: 1);
        await Future<void>.delayed(const Duration(milliseconds: 400));

        expect(vm.populatedItems.length, 1);
        expect(vm.hasUnavailableItems, isTrue);
        expect(vm.unavailableItemsMessage, contains('no longer available'));

        await vm.startCheckout();
        expect(service.createCalls, isEmpty);
      },
    );

    test('server totals are authoritative once known', () async {
      final vm = makeViewModel();
      await primeCart(vm);
      service.createResult = (key) => CreatePaymentIntentResult(
        checkoutSessionId: 'cs_$key',
        paymentIntentClientSecret: 'pi_secret',
        amountMinor: 123400,
        currency: 'pkr',
        expiresAt: DateTime.now().add(const Duration(minutes: 15)),
        totals: const CheckoutTotals(
          subtotal: 1200,
          deliveryFee: 500,
          discount: 466,
          total: 1234,
        ),
      );
      await vm.startCheckout();
      // Now finalizing; totals reflect the SERVER numbers, not the cart estimate.
      expect(vm.subtotal, 1200);
      expect(vm.discount, 466);
      expect(vm.total, 1234);
    });
  });

  group('CheckoutViewModel - success path', () {
    test(
      'webhook succeeded + orderId -> cart cleared, phase succeeded',
      () async {
        final vm = makeViewModel();
        await primeCart(vm);

        await vm.startCheckout();
        expect(vm.phase, CheckoutPhase.finalizing);
        expect(shoppingState.cartCount, greaterThan(0)); // NOT cleared yet

        // The webhook creates the order server-side; it lands in CustomerOrderState.
        db.addOrder(_order('ord_abc'));
        service
            .sessionController(service.lastCheckoutSessionId)
            .add(
              const CheckoutSessionUpdate(
                status: CheckoutSessionStatus.succeeded,
                orderId: 'ord_abc',
              ),
            );
        await Future<void>.delayed(const Duration(milliseconds: 100));

        expect(vm.phase, CheckoutPhase.succeeded);
        expect(vm.succeededOrderId, 'ord_abc');
        expect(shoppingState.cartCount, 0); // cleared ONLY on confirmed success
      },
    );

    test('PaymentSheet completing alone is NOT treated as success', () async {
      final vm = makeViewModel(finalizeTimeout: const Duration(seconds: 5));
      await primeCart(vm);
      await vm.startCheckout();
      // Sheet returned, but no session update yet.
      expect(vm.phase, CheckoutPhase.finalizing);
      expect(vm.succeededOrderId, isNull);
      expect(shoppingState.cartCount, 2);
    });

    test(
      'success removes ONLY the purchased lines - an item added during a slow '
      'finalize is kept (Phase 8.13.6 late-success reconciliation)',
      () async {
        final vm = makeViewModel(finalizeTimeout: const Duration(seconds: 5));
        await primeCart(vm); // mens-oxford-shirt x2
        await vm.startCheckout();
        expect(vm.phase, CheckoutPhase.finalizing);

        // Customer keeps shopping while the webhook is slow.
        await shoppingState.addToCart('luna-accent-chair', quantity: 1);
        await Future<void>.delayed(const Duration(milliseconds: 50));

        db.addOrder(_order('ord_partial'));
        service
            .sessionController(service.lastCheckoutSessionId)
            .add(
              const CheckoutSessionUpdate(
                status: CheckoutSessionStatus.succeeded,
                orderId: 'ord_partial',
              ),
            );
        await Future<void>.delayed(const Duration(milliseconds: 120));

        expect(vm.phase, CheckoutPhase.succeeded);
        expect(shoppingState.cartItems.map((c) => c.productId), [
          'luna-accent-chair',
        ]);
      },
    );

    test(
      'a "reserved" then "succeeded" sequence (3DS / processing) completes',
      () async {
        final vm = makeViewModel(finalizeTimeout: const Duration(seconds: 5));
        await primeCart(vm);
        await vm.startCheckout();
        final ctrl = service.sessionController(service.lastCheckoutSessionId);

        ctrl.add(
          const CheckoutSessionUpdate(status: CheckoutSessionStatus.reserved),
        );
        await Future<void>.delayed(const Duration(milliseconds: 30));
        expect(vm.phase, CheckoutPhase.finalizing);

        db.addOrder(_order('ord_3ds'));
        ctrl.add(
          const CheckoutSessionUpdate(
            status: CheckoutSessionStatus.succeeded,
            orderId: 'ord_3ds',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(vm.phase, CheckoutPhase.succeeded);
        expect(shoppingState.cartCount, 0);
      },
    );
  });

  group('CheckoutViewModel - cancellation / decline / failure keep the cart', () {
    test(
      'PaymentSheet cancelled -> idle, cart kept, SAME idempotency key',
      () async {
        final vm = makeViewModel();
        await primeCart(vm);
        service.presentError = const CheckoutPaymentException(
          CheckoutErrorKind.paymentSheetCancelled,
          'Payment cancelled. Your cart is saved — you can try again.',
        );
        await vm.startCheckout();

        expect(vm.phase, CheckoutPhase.idle);
        expect(vm.lastErrorKind, CheckoutErrorKind.paymentSheetCancelled);
        expect(shoppingState.cartCount, 2);
        final keyAfterCancel = service.createCalls.single;

        // Retry: reuses the SAME key (reservation still stands).
        service.presentError = null;
        vm.acknowledgeError();
        await vm.startCheckout();
        expect(service.createCalls, [keyAfterCancel, keyAfterCancel]);
      },
    );

    test('card declined -> idle, cart kept, retry with same key', () async {
      final vm = makeViewModel();
      await primeCart(vm);
      service.presentError = const CheckoutPaymentException(
        CheckoutErrorKind.cardDeclined,
        'Your card was declined.',
      );
      await vm.startCheckout();
      expect(vm.phase, CheckoutPhase.idle);
      expect(shoppingState.cartCount, 2);
      expect(service.createCalls.length, 1);
    });

    test(
      'session failed -> idle, cart kept, NEW idempotency key on retry',
      () async {
        final vm = makeViewModel(finalizeTimeout: const Duration(seconds: 5));
        await primeCart(vm);
        await vm.startCheckout();
        final firstKey = service.createCalls.single;

        service
            .sessionController(service.lastCheckoutSessionId)
            .add(
              const CheckoutSessionUpdate(status: CheckoutSessionStatus.failed),
            );
        await Future<void>.delayed(const Duration(milliseconds: 60));

        expect(vm.phase, CheckoutPhase.idle);
        expect(shoppingState.cartCount, 2);

        vm.acknowledgeError();
        await vm.startCheckout();
        expect(service.createCalls.length, 2);
        expect(service.createCalls[1], isNot(firstKey)); // fresh attempt
      },
    );

    test(
      'session expired behaves like failure (cart kept, fresh key)',
      () async {
        final vm = makeViewModel(finalizeTimeout: const Duration(seconds: 5));
        await primeCart(vm);
        await vm.startCheckout();
        final firstKey = service.createCalls.single;
        service
            .sessionController(service.lastCheckoutSessionId)
            .add(
              const CheckoutSessionUpdate(
                status: CheckoutSessionStatus.expired,
              ),
            );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(vm.phase, CheckoutPhase.idle);
        expect(shoppingState.cartCount, 2);
        vm.acknowledgeError();
        await vm.startCheckout();
        expect(service.createCalls[1], isNot(firstKey));
      },
    );

    test(
      'server INSUFFICIENT_STOCK -> idle, cart kept, fresh key next attempt',
      () async {
        final vm = makeViewModel();
        await primeCart(vm);
        service.createError = const CheckoutPaymentException(
          CheckoutErrorKind.insufficientStock,
          'Only 1 of Oxford Shirt left - you asked for 2.',
        );
        await vm.startCheckout();
        expect(vm.phase, CheckoutPhase.idle);
        expect(vm.error, contains('left'));
        expect(shoppingState.cartCount, 2);
        final firstKey = service.createCalls.single;

        service.createError = null;
        vm.acknowledgeError();
        await vm.startCheckout();
        expect(service.createCalls[1], isNot(firstKey));
      },
    );

    test(
      'network error on createPaymentIntent -> idle, cart kept, retry same key',
      () async {
        final vm = makeViewModel();
        await primeCart(vm);
        service.createError = const CheckoutPaymentException(
          CheckoutErrorKind.network,
          'Check your connection and try again.',
        );
        await vm.startCheckout();
        expect(vm.phase, CheckoutPhase.idle);
        expect(shoppingState.cartCount, 2);
        final firstKey = service.createCalls.single;

        service.createError = null;
        vm.acknowledgeError();
        await vm.startCheckout();
        expect(service.createCalls, [
          firstKey,
          firstKey,
        ]); // retryable, same key
      },
    );
  });

  group('CheckoutViewModel - webhook delay & timeout', () {
    test(
      'no session result before the timeout -> processingTimeout, cart kept',
      () async {
        final vm = makeViewModel(
          finalizeTimeout: const Duration(milliseconds: 80),
        );
        await primeCart(vm);
        await vm.startCheckout();
        expect(vm.phase, CheckoutPhase.finalizing);

        await Future<void>.delayed(const Duration(milliseconds: 150));
        expect(vm.phase, CheckoutPhase.processingTimeout);
        expect(shoppingState.cartCount, 2); // NOT cleared while processing
      },
    );

    test(
      'a late "succeeded" after the timeout still completes the order',
      () async {
        final vm = makeViewModel(
          finalizeTimeout: const Duration(milliseconds: 60),
        );
        await primeCart(vm);
        await vm.startCheckout();
        await Future<void>.delayed(const Duration(milliseconds: 120));
        expect(vm.phase, CheckoutPhase.processingTimeout);

        db.addOrder(_order('ord_late'));
        service
            .sessionController(service.lastCheckoutSessionId)
            .add(
              const CheckoutSessionUpdate(
                status: CheckoutSessionStatus.succeeded,
                orderId: 'ord_late',
              ),
            );
        await Future<void>.delayed(const Duration(milliseconds: 80));
        expect(vm.phase, CheckoutPhase.succeeded);
        expect(shoppingState.cartCount, 0);
      },
    );
  });

  group('CheckoutViewModel - duplicate taps & disposal', () {
    test('rapid double tap calls createPaymentIntent once', () async {
      final vm = makeViewModel();
      await primeCart(vm);
      final f1 = vm.startCheckout();
      final f2 = vm.startCheckout();
      await Future.wait([f1, f2]);
      expect(service.createCalls.length, 1);
    });

    test('tapping again while finalizing is ignored', () async {
      final vm = makeViewModel(finalizeTimeout: const Duration(seconds: 5));
      await primeCart(vm);
      await vm.startCheckout();
      expect(vm.phase, CheckoutPhase.finalizing);
      await vm.startCheckout();
      expect(service.createCalls.length, 1);
    });

    test(
      'dispose cancels the session listener - no further phase changes',
      () async {
        final vm = makeViewModel(finalizeTimeout: const Duration(seconds: 5));
        await primeCart(vm);
        await vm.startCheckout();
        final ctrl = service.sessionController(service.lastCheckoutSessionId);
        vm.dispose();

        db.addOrder(_order('ord_after_dispose'));
        ctrl.add(
          const CheckoutSessionUpdate(
            status: CheckoutSessionStatus.succeeded,
            orderId: 'ord_after_dispose',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 60));
        expect(vm.phase, CheckoutPhase.finalizing); // unchanged
        expect(shoppingState.cartCount, 2); // never cleared
      },
    );

    test('signed-out session cannot start checkout', () async {
      authState = AuthSessionState(); // no session
      final vm = makeViewModel();
      await primeCart(vm);
      await vm.startCheckout();
      expect(service.createCalls, isEmpty);
      expect(vm.error, contains('sign in'));
    });
  });
}
