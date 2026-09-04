/// Compile-time Stripe configuration.
///
/// The publishable key is supplied ONLY through secure local build
/// configuration - `--dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...` (or a
/// `--dart-define-from-file` JSON that is git-ignored). It is a *publishable*
/// key (safe to ship in a client binary), but it is deliberately NOT
/// hard-coded or committed so that the sandbox / live key is chosen at build
/// time, never baked into source control.
///
/// When the define is absent (`isConfigured == false`) the checkout flow
/// surfaces a clean "card payment is temporarily unavailable" message and
/// never attempts to talk to Stripe.
class StripeConfig {
  StripeConfig._();

  static const String publishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
  );

  static const String merchantDisplayName = 'TWin AR';

  static bool get isConfigured => publishableKey.isNotEmpty;

  /// Region the Phase 8.13 Cloud Functions are deployed to.
  static const String functionsRegion = 'us-central1';
}
