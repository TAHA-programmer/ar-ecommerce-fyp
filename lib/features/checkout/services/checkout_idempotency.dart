import 'dart:math';

/// Generates a stable idempotency key for ONE checkout attempt.
///
/// The same key is reused across retries of the same attempt (cancel /
/// decline / re-present) so the server returns the same reservation and the
/// same PaymentIntent - no duplicate reservation, no duplicate charge. A new
/// key is minted only once the prior attempt is terminal (succeeded / failed
/// / expired).
///
/// Shape: `ck_<millis>_<16 hex>` - 8-200 chars, matching the server's
/// `idempotencyKey` validation.
String generateCheckoutIdempotencyKey() {
  final rng = Random.secure();
  final hex = List<String>.generate(
    16,
    (_) => rng.nextInt(16).toRadixString(16),
  ).join();
  return 'ck_${DateTime.now().millisecondsSinceEpoch}_$hex';
}
