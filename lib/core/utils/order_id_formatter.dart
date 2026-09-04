/// Display-only shortening for order/payment ids.
///
/// Two id shapes exist in this app:
///
///  1. The Phase 8.9 interim client-generated pair -
///     `#TW<microseconds>_<random>` / `pay_<microseconds>_<random>`. The
///     client-side generator that produced these was removed in the Phase
///     8.13.6 security cutover, but ids of this shape still exist in
///     Firestore from earlier testing, so the formatter keeps handling
///     them. The timestamp half has no value to a customer or Admin reading
///     a card; the short random suffix is the real signal.
///  2. Phase 8.13's webhook-generated pair - `ord_<40-hex-digest>` /
///     `pay_<40-hex-digest>`, derived deterministically from the Stripe
///     PaymentIntent id (see `functions/src/lib/webhook.ts`). At 44
///     characters these overflow every card row if shown raw.
///
/// [short] is purely cosmetic: it never changes what's stored, searched,
/// looked up, or passed as a route argument - every call site keeps using
/// [OrderModel.id]/[PaymentRecord.paymentId] as-is for anything other than
/// the `Text` it renders. Any id that doesn't match a known shape (e.g.
/// legacy/mock test fixtures like `#TW00000001` or `pay_checkout`) is
/// returned unchanged rather than mangled.
class OrderIdFormatter {
  OrderIdFormatter._();

  /// Matches ONLY the real generator shape - a non-digit prefix, then a
  /// long (>=10 digit) microsecond timestamp, then `_`, then the 6-12
  /// character random suffix. Deliberately strict: an early looser version
  /// of this (matching on "contains an underscore") mangled unrelated
  /// mock/test fixture ids that merely happen to contain an underscore
  /// without being real generator-shaped ids - e.g. `pay_old`/`pay_checkout`
  /// collapsed to `OLD`/`CHECKOUT`, losing their distinguishing prefix and
  /// occasionally colliding with each other on screen. Anything that
  /// doesn't match this exact shape is returned completely unchanged.
  static final RegExp _generatorShape = RegExp(
    r'^([^0-9]*)(\d{10,})_([a-z0-9]{6,12})$',
  );

  /// The Phase 8.13 webhook's deterministic ids: a literal `ord_` / `pay_`
  /// prefix, then a long lowercase-hex digest (40 chars from the SHA-256).
  /// Nothing else in the app produces this shape - the legacy generator's
  /// `pay_<digits>_<suffix>` always has an internal `_`, so it never
  /// matches. An order collapses to `#<first 8 hex, upper>` (the same
  /// `#`-prefixed, ~10-char form the legacy `#TW…` ids already shorten to);
  /// a payment keeps its readable `pay_` prefix.
  static final RegExp _webhookShape = RegExp(r'^(ord|pay)_([0-9a-f]{16,64})$');

  static String short(String id) {
    final generator = _generatorShape.firstMatch(id);
    if (generator != null) {
      final prefix = generator.group(1) ?? '';
      final suffix = generator.group(3) ?? '';
      if (suffix.isNotEmpty) return '$prefix${suffix.toUpperCase()}';
    }

    final webhook = _webhookShape.firstMatch(id);
    if (webhook != null) {
      final kind = webhook.group(1);
      final digest = webhook.group(2)!;
      final head = digest.substring(0, 8).toUpperCase();
      return kind == 'pay' ? 'pay_$head' : '#$head';
    }

    return id;
  }
}
