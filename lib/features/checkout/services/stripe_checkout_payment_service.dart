import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_stripe/flutter_stripe.dart';

import '../../../core/config/stripe_config.dart';
import '../../../core/theme/app_colors.dart';
import '../models/checkout_payment_models.dart';
import 'checkout_payment_service.dart';

/// Real [CheckoutPaymentService]: `createPaymentIntent` (Cloud Functions,
/// `us-central1`) + Stripe PaymentSheet + a `checkoutSessions/{id}` listener.
///
/// It never writes any Firestore document - the callable and the webhook own
/// every checkout-session / stock / order / payment write.
class StripeCheckoutPaymentService implements CheckoutPaymentService {
  final FirebaseFunctions? _injectedFunctions;
  final FirebaseFirestore? _injectedFirestore;

  StripeCheckoutPaymentService({
    FirebaseFunctions? functions,
    FirebaseFirestore? firestore,
  }) : _injectedFunctions = functions,
       _injectedFirestore = firestore;

  // Resolved on first use, not at construction - the Firebase singletons
  // require `Firebase.initializeApp()` to have run, and this service is
  // constructed eagerly by the provider tree (for the reconciler). Nothing
  // here is touched until an actual checkout / reconciliation call.
  FirebaseFunctions get _functions =>
      _injectedFunctions ??
      FirebaseFunctions.instanceFor(region: StripeConfig.functionsRegion);

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  @override
  bool get isConfigured => StripeConfig.isConfigured;

  static const _genericSetupError =
      'Something went wrong setting up your payment. Please try again.';
  static const _networkError =
      'We couldn\'t reach the payment service. Check your connection and try again.';

  @override
  Future<CreatePaymentIntentResult> createPaymentIntent({
    required List<CheckoutLineItemRequest> items,
    required String addressId,
    required String idempotencyKey,
  }) async {
    if (!isConfigured) {
      throw const CheckoutPaymentException(
        CheckoutErrorKind.notConfigured,
        'Card payment is temporarily unavailable. Please try again later.',
      );
    }

    final HttpsCallableResult result;
    try {
      final callable = _functions.httpsCallable(
        'createPaymentIntent',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      result = await callable.call(<String, dynamic>{
        'items': items.map((i) => i.toMap()).toList(),
        'addressId': addressId,
        'idempotencyKey': idempotencyKey,
      });
    } on FirebaseFunctionsException catch (e) {
      throw _mapFunctionsException(e);
    } catch (_) {
      throw const CheckoutPaymentException(
        CheckoutErrorKind.network,
        _networkError,
      );
    }

    final data = _asStringMap(result.data);
    if (data == null ||
        (data['paymentIntentClientSecret'] ?? '').toString().isEmpty) {
      throw const CheckoutPaymentException(
        CheckoutErrorKind.unknown,
        _genericSetupError,
      );
    }
    return CreatePaymentIntentResult.fromMap(data);
  }

  @override
  Future<void> presentPaymentSheet({required String clientSecret}) async {
    if (!isConfigured) {
      throw const CheckoutPaymentException(
        CheckoutErrorKind.notConfigured,
        'Card payment is temporarily unavailable. Please try again later.',
      );
    }
    try {
      await Stripe.instance.initPaymentSheet(
        paymentSheetParameters: SetupPaymentSheetParameters(
          paymentIntentClientSecret: clientSecret,
          merchantDisplayName: StripeConfig.merchantDisplayName,
          style: ThemeMode.light,
          appearance: const PaymentSheetAppearance(
            colors: PaymentSheetAppearanceColors(primary: AppColors.primary),
          ),
        ),
      );
      await Stripe.instance.presentPaymentSheet();
    } on StripeException catch (e) {
      if (e.error.code == FailureCode.Canceled) {
        throw const CheckoutPaymentException(
          CheckoutErrorKind.paymentSheetCancelled,
          'Payment cancelled. Your cart is saved — you can try again.',
        );
      }
      throw const CheckoutPaymentException(
        CheckoutErrorKind.cardDeclined,
        'Your payment could not be completed. Please try a different card.',
      );
    } on CheckoutPaymentException {
      rethrow;
    } catch (_) {
      throw const CheckoutPaymentException(
        CheckoutErrorKind.unknown,
        'Something went wrong with the payment. Please try again.',
      );
    }
  }

  @override
  Stream<CheckoutSessionUpdate> watchSession(String sessionId) {
    return _firestore
        .collection('checkoutSessions')
        .doc(sessionId)
        .snapshots()
        .map((snap) {
          final data = snap.data();
          if (data == null) {
            return const CheckoutSessionUpdate(
              status: CheckoutSessionStatus.reserved,
            );
          }
          final orderId = data['orderId'];
          return CheckoutSessionUpdate(
            status: checkoutSessionStatusFrom(data['status']),
            orderId: orderId is String && orderId.isNotEmpty ? orderId : null,
            totals: data.containsKey('total')
                ? CheckoutTotals.fromMap(data.cast<String, dynamic>())
                : null,
          );
        });
  }

  @override
  Future<List<PurchasedLine>> recentlyPurchasedLines(String uid) async {
    if (uid.isEmpty) return const [];
    try {
      // Single-field `where` (auto-indexed) + a small bound. `status` and
      // `orderId` are filtered in Dart so no composite index is needed. The
      // rule (`isOwner(resource.data.userId)`) makes this query provably safe.
      final snap = await _firestore
          .collection('checkoutSessions')
          .where('userId', isEqualTo: uid)
          .limit(40)
          .get();

      final lines = <PurchasedLine>[];
      for (final doc in snap.docs) {
        final data = doc.data();
        if (data['status'] != 'succeeded') continue;
        final orderId = data['orderId'];
        if (orderId is! String || orderId.isEmpty) continue;
        final items = data['items'];
        if (items is! List) continue;
        for (final raw in items) {
          if (raw is! Map) continue;
          final line = PurchasedLine.fromSessionItem(
            raw.cast<String, dynamic>(),
          );
          if (line.isValid) lines.add(line);
        }
      }
      return lines;
    } catch (_) {
      // Best-effort: a read failure just means no reconciliation this pass.
      return const [];
    }
  }

  Map<String, dynamic>? _asStringMap(Object? raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  CheckoutPaymentException _mapFunctionsException(
    FirebaseFunctionsException e,
  ) {
    final details = e.details;
    final appCode = details is Map ? details['appCode']?.toString() : null;
    final serverMsg = (e.message ?? '').trim();

    switch (appCode) {
      case 'ADDRESS_NOT_FOUND':
      case 'ADDRESS_INCOMPLETE':
        return CheckoutPaymentException(
          CheckoutErrorKind.addressProblem,
          serverMsg.isNotEmpty
              ? serverMsg
              : 'There is a problem with your delivery address. Please check it and try again.',
        );
      case 'PRODUCT_UNAVAILABLE':
      case 'VARIANT_UNAVAILABLE':
        return CheckoutPaymentException(
          CheckoutErrorKind.productUnavailable,
          serverMsg.isNotEmpty
              ? serverMsg
              : 'One or more items are no longer available. Please review your cart.',
        );
      case 'OUT_OF_STOCK':
      case 'INSUFFICIENT_STOCK':
        return CheckoutPaymentException(
          CheckoutErrorKind.insufficientStock,
          serverMsg.isNotEmpty
              ? serverMsg
              : 'One or more items are out of stock. Please review your cart.',
        );
      case 'CHECKOUT_ALREADY_COMPLETED':
        return const CheckoutPaymentException(
          CheckoutErrorKind.checkoutClosed,
          'This checkout has already been completed.',
        );
      case 'CHECKOUT_ATTEMPT_CLOSED':
        return const CheckoutPaymentException(
          CheckoutErrorKind.checkoutClosed,
          'This checkout attempt is closed. Please start again.',
        );
      case 'CHECKOUT_EXPIRED':
        return const CheckoutPaymentException(
          CheckoutErrorKind.reservationExpired,
          'Your checkout timed out. Please try again.',
        );
      case 'PAYMENT_AMOUNT_TOO_SMALL':
      case 'ORDER_TOTAL_INVALID':
        return const CheckoutPaymentException(
          CheckoutErrorKind.unknown,
          'This order total can\'t be processed. Please review your cart.',
        );
      case 'PAYMENT_PROVIDER_ERROR':
      case 'RESERVATION_CONFLICT':
        return const CheckoutPaymentException(
          CheckoutErrorKind.network,
          _networkError,
        );
    }

    switch (e.code) {
      case 'unauthenticated':
        return const CheckoutPaymentException(
          CheckoutErrorKind.unknown,
          'Please sign in again and retry your order.',
        );
      case 'unavailable':
      case 'deadline-exceeded':
        return const CheckoutPaymentException(
          CheckoutErrorKind.network,
          _networkError,
        );
    }
    return const CheckoutPaymentException(
      CheckoutErrorKind.unknown,
      _genericSetupError,
    );
  }
}
