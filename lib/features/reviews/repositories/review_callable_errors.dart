/// Maps a `submitReview`/`deleteReview`/`reportReview` callable failure to a
/// clean, customer-safe message - the client-side mirror of
/// `functions/src/lib/reviews/errors.ts`'s `appCode`s.
///
/// Kept as a small, pure, string-in/string-out function - deliberately NOT a
/// method that takes a `FirebaseFunctionsException` directly (its
/// constructor is `@protected` in `cloud_functions_platform_interface`, so
/// it cannot be constructed outside that package - exactly why
/// `FirebaseVirtualTryOnService._mapFunctionsException` has no direct unit
/// test either). Extracting the mapping itself into plain strings is what
/// makes every branch here independently testable without a Functions
/// emulator.
///
/// [appCode] is the stable code the server puts in `details.appCode`;
/// [grpcCode] is the callable's own `code` (e.g. `unavailable`); [message]
/// is the server's own already customer-safe message, used verbatim when
/// present (the server messages ARE the source of truth - these fallbacks
/// only cover a malformed/absent server message).
String mapReviewCallableError({
  required String? appCode,
  String? grpcCode,
  String? message,
}) {
  final serverMessage = (message ?? '').trim();
  String of(String fallback) =>
      serverMessage.isNotEmpty ? serverMessage : fallback;

  switch (appCode) {
    case 'UNAUTHENTICATED':
      return of('You must be signed in to do that.');
    case 'INVALID_REQUEST':
      return of('Something went wrong with that request. Please try again.');
    case 'NOT_ELIGIBLE':
      return of('You can only review products from a delivered order.');
    case 'EDIT_WINDOW_EXPIRED':
      return of(
        'This review can no longer be edited - the 30-day edit window has '
        'passed.',
      );
    case 'REVIEW_NOT_FOUND':
      return of('This review no longer exists.');
    case 'FORBIDDEN':
      return of("You don't have access to that review.");
    case 'ADMIN_REQUIRED':
      return of('Admin access is required for this action.');
    case 'CANNOT_REPORT_OWN_REVIEW':
      return of("You can't report your own review.");
    case 'INTERNAL':
      return of('Something went wrong. Please try again.');
    default:
      if (grpcCode == 'unavailable' || grpcCode == 'deadline-exceeded') {
        return 'Network error. Please check your connection and try again.';
      }
      return of('Something went wrong. Please try again.');
  }
}
