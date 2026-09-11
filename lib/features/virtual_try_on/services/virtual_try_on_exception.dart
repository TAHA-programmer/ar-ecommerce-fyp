/// The reason a Virtual Try-On step could not complete (Phase 9.3 Stage 5).
/// Exact mirror of the callable's `VtoAppErrorCode` union
/// (`functions/src/lib/tryOn/errors.ts`) plus two client-only kinds
/// (`network`, `unknown`) — the ViewModel maps each kind to an honest,
/// already-approved customer message; the raw callable/Firestore/Storage
/// error text is never shown.
enum VirtualTryOnErrorKind {
  /// The customer is not signed in (or their session ended) when a call that
  /// requires auth was attempted. Client-detected as well as server-mapped —
  /// see [VirtualTryOnException.notSignedIn].
  notSignedIn,

  /// `INVALID_REQUEST` — malformed request (should be unreachable from the
  /// UI; the allow-list is built by [VirtualTryOnService], never the user).
  invalidRequest,

  /// `CONSENT_REQUIRED` — the request didn't carry `consent: true`.
  consentRequired,

  /// `PRODUCT_UNAVAILABLE` — the product is no longer published/active.
  productUnavailable,

  /// `PRODUCT_NOT_ELIGIBLE` — not a Virtual Try-On product / disabled / no
  /// valid contract.
  productNotEligible,

  /// `VARIANT_UNAVAILABLE` — the selected colour or size isn't offered.
  variantUnavailable,

  /// `GARMENT_UNAVAILABLE` — no renderable garment asset for that colour.
  garmentUnavailable,

  /// `FORBIDDEN` — the session doesn't belong to this caller.
  forbidden,

  /// `SESSION_ATTEMPT_CLOSED` — this idempotency key's attempt already ended
  /// (failed/expired); the caller must mint a new key.
  sessionAttemptClosed,

  /// `SESSION_IN_PROGRESS` — a generation for this exact attempt is already
  /// running.
  sessionInProgress,

  /// `RATE_LIMITED` — per-user hourly/daily cap reached.
  rateLimited,

  /// `GLOBAL_LIMIT_REACHED` — the server-enforced daily circuit breaker.
  globalLimitReached,

  /// `PHOTO_MISSING` — the server could not find the uploaded photo.
  photoMissing,

  /// `PHOTO_INVALID` — the uploaded photo failed server-side validation.
  photoInvalid,

  /// `PROVIDER_UNAVAILABLE` — the image provider could not be reached.
  providerUnavailable,

  /// `PROVIDER_REFUSED` — the provider declined to generate for this photo.
  providerRefused,

  /// `TIMEOUT` — generation took too long.
  timeout,

  /// Client-detected network/connectivity failure — never reached the server.
  network,

  /// Anything else — a generic, safe fallback.
  unknown,
}

/// Thrown by [VirtualTryOnService] for every non-success outcome. Carries a
/// machine [kind] and an already customer-safe [message] — never the raw
/// provider/Firestore/Storage error text.
class VirtualTryOnException implements Exception {
  final VirtualTryOnErrorKind kind;
  final String message;

  const VirtualTryOnException(this.kind, this.message);

  const VirtualTryOnException.notSignedIn()
    : kind = VirtualTryOnErrorKind.notSignedIn,
      message = 'Please sign in to use Virtual Try-On.';

  const VirtualTryOnException.network()
    : kind = VirtualTryOnErrorKind.network,
      message = "You're offline — check your connection and try again.";

  /// `true` for a failure where the photo the customer already has in memory
  /// is very likely still fine to retry with (rate limit / transient /
  /// timeout / eligibility) — as opposed to a photo-specific rejection,
  /// where the customer must pick a different photo.
  bool get isRetryableWithSamePhoto => switch (kind) {
    VirtualTryOnErrorKind.photoMissing ||
    VirtualTryOnErrorKind.photoInvalid ||
    VirtualTryOnErrorKind.providerRefused => false,
    _ => true,
  };

  @override
  String toString() => 'VirtualTryOnException($kind, $message)';
}
