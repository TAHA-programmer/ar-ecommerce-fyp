import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/virtual_try_on/services/virtual_try_on_idempotency.dart';

void main() {
  test('generates unique keys with the expected shape', () {
    final a = generateVirtualTryOnIdempotencyKey();
    final b = generateVirtualTryOnIdempotencyKey();

    expect(a, isNot(equals(b)));
    expect(a.startsWith('vto_'), true);
    expect(a.length, greaterThanOrEqualTo(8));
    expect(a.length, lessThanOrEqualTo(200));
  });
}
