import 'dart:math';

/// Generates a stable idempotency key for ONE Virtual Try-On generation
/// attempt (Phase 9.3 Stage 5) — exact mirror of
/// `generateCheckoutIdempotencyKey` (`checkout_idempotency.dart`).
///
/// The same key is reused across a retry of the same attempt (the customer's
/// photo is still valid and only a transient failure occurred); a NEW key is
/// minted only once the prior attempt is terminal (succeeded / failed /
/// closed) or the customer picks a different photo — this is what makes
/// `generateTryOn`'s duplicate-request protection (UC-15 4B) actually work.
///
/// Shape: `vto_<millis>_<16 hex>` — 8-200 chars, matching the server's
/// `idempotencyKey` validation in `functions/src/lib/tryOn/validation.ts`.
String generateVirtualTryOnIdempotencyKey() {
  final rng = Random.secure();
  final hex = List<String>.generate(
    16,
    (_) => rng.nextInt(16).toRadixString(16),
  ).join();
  return 'vto_${DateTime.now().millisecondsSinceEpoch}_$hex';
}
