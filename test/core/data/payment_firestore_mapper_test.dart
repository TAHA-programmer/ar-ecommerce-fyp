import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/payment_firestore_mapper.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';

PaymentRecord _payment() {
  return PaymentRecord(
    paymentId: 'pay_1',
    userId: 'alice',
    orderId: '#TW1',
    amount: 1050,
    method: PaymentMethod.stripeCard,
    status: PaymentStatus.paid,
    createdAt: DateTime(2026, 1, 1),
  );
}

void main() {
  group('payment_firestore_mapper', () {
    test(
      'toFirestoreCreateMap -> paymentRecordFromFirestore round-trips '
      'every field except createdAt (which uses serverTimestamp on write)',
      () {
        final payment = _payment();
        final map = payment.toFirestoreCreateMap();
        final resolvedMap = {
          ...map,
          'createdAt': Timestamp.fromDate(payment.createdAt),
        };

        final reloaded = paymentRecordFromFirestore('pay_1', resolvedMap);

        expect(reloaded.paymentId, 'pay_1');
        expect(reloaded.userId, 'alice');
        expect(reloaded.orderId, '#TW1');
        expect(reloaded.amount, 1050);
        expect(reloaded.method, PaymentMethod.stripeCard);
        expect(reloaded.status, PaymentStatus.paid);
        expect(reloaded.createdAt, payment.createdAt);
      },
    );

    test('toFirestoreCreateMap never includes "paymentId" (it is the '
        'document key, not a field)', () {
      expect(
        _payment().toFirestoreCreateMap().containsKey('paymentId'),
        isFalse,
      );
    });

    test('a present-but-wrong-typed field never throws - falls back to a '
        'safe default', () {
      final malformed = <String, dynamic>{
        'userId': 123,
        'orderId': null,
        'amount': 'not-a-number',
        'method': 99,
        'status': 'bogus',
        'createdAt': null,
      };

      expect(
        () => paymentRecordFromFirestore('pay-malformed', malformed),
        returnsNormally,
      );

      final result = paymentRecordFromFirestore('pay-malformed', malformed);
      expect(result.userId, '');
      expect(result.orderId, '');
      expect(result.amount, 0);
      expect(result.status, PaymentStatus.pending);
    });
  });
}
