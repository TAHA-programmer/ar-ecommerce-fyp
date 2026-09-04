import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/utils/order_id_formatter.dart';

void main() {
  group('OrderIdFormatter.short - Phase 8.9 client-generated ids', () {
    test('shortens a real generator-shaped order id to prefix + suffix', () {
      expect(
        OrderIdFormatter.short('#TW1755781234567890_a1b2c3d4'),
        '#TWA1B2C3D4',
      );
    });

    test('shortens a real generator-shaped payment id to prefix + suffix', () {
      expect(
        OrderIdFormatter.short('pay_1755781234567890_a1b2c3d4'),
        'pay_A1B2C3D4',
      );
    });

    test('leaves a legacy/fixture id with no underscore unchanged', () {
      expect(OrderIdFormatter.short('#TW12345678'), '#TW12345678');
      expect(OrderIdFormatter.short('#TAR123'), '#TAR123');
      expect(OrderIdFormatter.short('TW123'), 'TW123');
    });

    test('leaves a mock/test fixture id that merely CONTAINS an underscore '
        '(but does not match the real generator shape) completely unchanged '
        '- regression guard for a real bug: an earlier looser version '
        'mangled these into their bare suffix (e.g. "pay_old" -> "OLD"), '
        'occasionally colliding across different fixtures on screen', () {
      expect(OrderIdFormatter.short('pay_old'), 'pay_old');
      expect(OrderIdFormatter.short('pay_new'), 'pay_new');
      expect(OrderIdFormatter.short('pay_mid'), 'pay_mid');
      expect(OrderIdFormatter.short('pay_checkout'), 'pay_checkout');
      expect(OrderIdFormatter.short('pay_no_order'), 'pay_no_order');
      expect(OrderIdFormatter.short('pay_1'), 'pay_1');
    });
  });

  group('OrderIdFormatter.short - Phase 8.13 webhook-generated ids', () {
    // ord_/pay_ + a 40-char lowercase-hex SHA-256 slice (see
    // functions/src/lib/webhook.ts deterministicOrderId/deterministicPaymentId).
    const orderId = 'ord_a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4';
    const paymentId = 'pay_a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4';

    test('collapses a webhook order id to a "#" + first 8 hex (upper)', () {
      expect(OrderIdFormatter.short(orderId), '#A1B2C3D4');
    });

    test('collapses a webhook payment id to "pay_" + first 8 hex (upper)', () {
      expect(OrderIdFormatter.short(paymentId), 'pay_A1B2C3D4');
    });

    test('the shortened form is display-length, not the full 44 chars', () {
      expect(OrderIdFormatter.short(orderId).length, lessThan(12));
      expect(OrderIdFormatter.short(paymentId).length, lessThan(14));
    });

    test('a webhook order id with an all-digit digest still shortens', () {
      expect(
        OrderIdFormatter.short('ord_1234567890123456789012345678901234567890'),
        '#12345678',
      );
    });

    test('leaves an ord_/pay_ prefixed id that is NOT a hex digest unchanged '
        '(e.g. a non-generator fixture)', () {
      expect(OrderIdFormatter.short('ord_test'), 'ord_test');
      expect(
        OrderIdFormatter.short('pay_reservation_lost'),
        'pay_reservation_lost',
      );
      // too short to be a real digest
      expect(OrderIdFormatter.short('ord_abc123'), 'ord_abc123');
    });
  });

  group('OrderIdFormatter.short - contract', () {
    test('never changes the value used for lookups - display only', () {
      // Regression guard: this is the whole point of the formatter -
      // callers must keep using the real id for navigation/search/storage
      // and only ever pass it through OrderIdFormatter.short for display.
      for (final realId in const [
        '#TW1755781234567890_a1b2c3d4',
        'ord_a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4',
        'pay_a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4',
      ]) {
        expect(OrderIdFormatter.short(realId), isNot(realId));
      }
    });

    test('is idempotent on its own output', () {
      const orderId = 'ord_a1b2c3d4e5f60718293a4b5c6d7e8f90a1b2c3d4';
      final once = OrderIdFormatter.short(orderId);
      expect(OrderIdFormatter.short(once), once);
    });

    test('returns an empty string unchanged', () {
      expect(OrderIdFormatter.short(''), '');
    });
  });
}
