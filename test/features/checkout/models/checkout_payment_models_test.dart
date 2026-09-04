import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/checkout/models/checkout_payment_models.dart';
import 'package:twin_ar/features/checkout/services/checkout_idempotency.dart';

void main() {
  group('CreatePaymentIntentResult.fromMap', () {
    test('parses the createPaymentIntent callable response', () {
      final r = CreatePaymentIntentResult.fromMap({
        'checkoutSessionId': 'cs_abc',
        'paymentIntentClientSecret': 'pi_abc_secret_123',
        'amount': 750000,
        'currency': 'pkr',
        'status': 'reserved',
        'expiresAt': 1893456000000,
        'totals': {
          'subtotal': 8000,
          'deliveryFee': 500,
          'discount': 1000,
          'total': 7500,
        },
      });
      expect(r.checkoutSessionId, 'cs_abc');
      expect(r.paymentIntentClientSecret, 'pi_abc_secret_123');
      expect(r.amountMinor, 750000);
      expect(r.currency, 'pkr');
      expect(r.totals.total, 7500);
      expect(r.expiresAt.millisecondsSinceEpoch, 1893456000000);
    });

    test('tolerates a missing/blank totals map', () {
      final r = CreatePaymentIntentResult.fromMap({
        'checkoutSessionId': 'cs',
        'paymentIntentClientSecret': 'pi_secret',
      });
      expect(r.totals.total, 0);
      expect(r.amountMinor, 0);
    });
  });

  group('checkoutSessionStatusFrom', () {
    test('maps each server status string', () {
      expect(
        checkoutSessionStatusFrom('reserved'),
        CheckoutSessionStatus.reserved,
      );
      expect(
        checkoutSessionStatusFrom('succeeded'),
        CheckoutSessionStatus.succeeded,
      );
      expect(checkoutSessionStatusFrom('failed'), CheckoutSessionStatus.failed);
      expect(
        checkoutSessionStatusFrom('expired'),
        CheckoutSessionStatus.expired,
      );
      expect(checkoutSessionStatusFrom('weird'), CheckoutSessionStatus.unknown);
      expect(checkoutSessionStatusFrom(null), CheckoutSessionStatus.unknown);
    });
  });

  group('CheckoutSessionUpdate', () {
    test(
      'isSucceededWithOrder requires both succeeded AND a non-empty orderId',
      () {
        expect(
          const CheckoutSessionUpdate(
            status: CheckoutSessionStatus.succeeded,
            orderId: 'ord_1',
          ).isSucceededWithOrder,
          isTrue,
        );
        expect(
          const CheckoutSessionUpdate(
            status: CheckoutSessionStatus.succeeded,
          ).isSucceededWithOrder,
          isFalse,
        );
        expect(
          const CheckoutSessionUpdate(
            status: CheckoutSessionStatus.succeeded,
            orderId: '',
          ).isSucceededWithOrder,
          isFalse,
        );
      },
    );

    test('isTerminalFailure is true for failed and expired only', () {
      expect(
        const CheckoutSessionUpdate(
          status: CheckoutSessionStatus.failed,
        ).isTerminalFailure,
        isTrue,
      );
      expect(
        const CheckoutSessionUpdate(
          status: CheckoutSessionStatus.expired,
        ).isTerminalFailure,
        isTrue,
      );
      expect(
        const CheckoutSessionUpdate(
          status: CheckoutSessionStatus.reserved,
        ).isTerminalFailure,
        isFalse,
      );
    });
  });

  group('generateCheckoutIdempotencyKey', () {
    test('is unique per call and matches the server key shape', () {
      final a = generateCheckoutIdempotencyKey();
      final b = generateCheckoutIdempotencyKey();
      expect(a, isNot(b));
      expect(a, matches(RegExp(r'^ck_\d+_[0-9a-f]{16}$')));
      expect(a.length, greaterThanOrEqualTo(8));
      expect(a.length, lessThanOrEqualTo(200));
    });
  });

  group('CheckoutLineItemRequest.toMap', () {
    test('omits null variants, keeps present ones', () {
      expect(
        const CheckoutLineItemRequest(productId: 'p', quantity: 2).toMap(),
        {'productId': 'p', 'quantity': 2},
      );
      expect(
        const CheckoutLineItemRequest(
          productId: 'p',
          quantity: 1,
          selectedColor: 'black',
          selectedSize: 'm',
        ).toMap(),
        {
          'productId': 'p',
          'quantity': 1,
          'selectedColor': 'black',
          'selectedSize': 'm',
        },
      );
    });
  });
}
