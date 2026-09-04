import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/checkout/models/checkout_payment_models.dart';
import 'package:twin_ar/features/checkout/services/checkout_payment_service.dart';
import 'package:twin_ar/features/checkout/viewmodels/checkout_viewmodel.dart';
import 'package:twin_ar/features/checkout/views/checkout_payment_view.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

class _FakeService implements CheckoutPaymentService {
  _FakeService();
  @override
  bool isConfigured = true;

  int createCalls = 0;
  int presentCalls = 0;
  CheckoutPaymentException? presentError;
  final _controllers = <String, StreamController<CheckoutSessionUpdate>>{};

  @override
  Future<CreatePaymentIntentResult> createPaymentIntent({
    required List<CheckoutLineItemRequest> items,
    required String addressId,
    required String idempotencyKey,
  }) async {
    createCalls++;
    return CreatePaymentIntentResult(
      checkoutSessionId: 'cs_$idempotencyKey',
      paymentIntentClientSecret: 'pi_secret',
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
  }

  @override
  Future<void> presentPaymentSheet({required String clientSecret}) async {
    presentCalls++;
    if (presentError != null) throw presentError!;
  }

  @override
  Stream<CheckoutSessionUpdate> watchSession(String sessionId) => _controllers
      .putIfAbsent(sessionId, () => StreamController.broadcast())
      .stream;

  @override
  Future<List<PurchasedLine>> recentlyPurchasedLines(String uid) async =>
      const [];
}

AuthSessionState _auth() => AuthSessionState()
  ..setSession(
    AuthResult.success(
      userId: 'test-uid',
      email: 'test@twinar.com',
      role: UserRole.customer,
    ),
  );

AddressDraft _draft() => AddressDraft(
  label: 'Home',
  fullName: 'Test User',
  phoneNumber: '03001234567',
  addressLine1: '123 Test St',
  city: 'Karachi',
  provinceOrState: 'Sindh',
  postalCode: '74000',
);

void main() {
  late CustomerShoppingState shoppingState;
  late CustomerAddressState addressState;
  late CustomerOrderState orderState;
  late MockCommerceDatabase db;
  late MockProductDetailsRepository repo;
  late _FakeService service;

  setUp(() {
    shoppingState = CustomerShoppingState(
      MockFavoritesRepository(),
      MockCartRepository(),
    );
    addressState = CustomerAddressState(MockAddressRepository());
    db = MockCommerceDatabase();
    orderState = CustomerOrderState(db);
    repo = MockProductDetailsRepository(db, simulateDelay: false);
    service = _FakeService();
  });

  CheckoutViewModel makeVm() => CheckoutViewModel(
    shoppingState,
    addressState,
    repo,
    _auth(),
    service,
    orderState,
    finalizeTimeout: const Duration(seconds: 5),
  );

  Widget wrap(CheckoutViewModel vm) => MaterialApp(
    home: ChangeNotifierProvider<CheckoutViewModel>.value(
      value: vm,
      child: const CheckoutPaymentView(),
    ),
  );

  testWidgets('shows the missing-address state', (tester) async {
    await tester.pumpWidget(wrap(makeVm()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('No address selected'), findsOneWidget);
  });

  testWidgets('shows the empty-cart state once an address exists', (
    tester,
  ) async {
    await addressState.addAddress(_draft());
    await tester.pumpWidget(wrap(makeVm()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Your cart is empty'), findsOneWidget);
  });

  testWidgets(
    'renders the "Pay Securely With Stripe" button for a primed cart',
    (tester) async {
      await addressState.addAddress(_draft());
      await shoppingState.addToCart('mens-oxford-shirt', quantity: 1);
      final vm = makeVm();
      await tester.pumpWidget(wrap(vm));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Pay Securely With Stripe'), findsOneWidget);
    },
  );

  testWidgets('paymentUnavailable state disables pay + shows a message', (
    tester,
  ) async {
    service.isConfigured = false;
    await addressState.addAddress(_draft());
    await shoppingState.addToCart('mens-oxford-shirt', quantity: 1);
    final vm = makeVm();
    await tester.pumpWidget(wrap(vm));
    await tester.pump(const Duration(milliseconds: 300));

    expect(
      find.text(
        'Card payment is temporarily unavailable. Please try again later.',
      ),
      findsOneWidget,
    );
    final button = tester.widget<ElevatedButton>(
      find.ancestor(
        of: find.text('Pay Securely With Stripe'),
        matching: find.byType(ElevatedButton),
      ),
    );
    expect(button.onPressed, isNull); // disabled
  });

  testWidgets('the "processing" card appears after the webhook timeout', (
    tester,
  ) async {
    await addressState.addAddress(_draft());
    await shoppingState.addToCart('mens-oxford-shirt', quantity: 1);
    final vm = CheckoutViewModel(
      shoppingState,
      addressState,
      repo,
      _auth(),
      service,
      orderState,
      finalizeTimeout: const Duration(milliseconds: 100),
    );
    await tester.pumpWidget(wrap(vm));
    await tester.pump(const Duration(milliseconds: 300));

    // Drive the flow via the ViewModel (the pay button sits below the fold in
    // the default 800x600 test viewport).
    await vm.startCheckout();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250)); // past the timeout
    await tester.pump();

    expect(vm.phase, CheckoutPhase.processingTimeout);
    expect(
      find.text('Payment received — finalizing your order'),
      findsOneWidget,
    );
    expect(find.text('Go to My Orders'), findsOneWidget);
  });
}
