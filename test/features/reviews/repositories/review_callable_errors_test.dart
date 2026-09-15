import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/repositories/review_callable_errors.dart';

void main() {
  group('mapReviewCallableError', () {
    test('UNAUTHENTICATED falls back to a clean sign-in message', () {
      expect(
        mapReviewCallableError(appCode: 'UNAUTHENTICATED'),
        'You must be signed in to do that.',
      );
    });

    test('NOT_ELIGIBLE falls back to the delivered-order message', () {
      expect(
        mapReviewCallableError(appCode: 'NOT_ELIGIBLE'),
        'You can only review products from a delivered order.',
      );
    });

    test('EDIT_WINDOW_EXPIRED falls back to the 30-day window message', () {
      expect(
        mapReviewCallableError(appCode: 'EDIT_WINDOW_EXPIRED'),
        'This review can no longer be edited - the 30-day edit window has '
        'passed.',
      );
    });

    test('REVIEW_NOT_FOUND falls back to a clean not-found message', () {
      expect(
        mapReviewCallableError(appCode: 'REVIEW_NOT_FOUND'),
        'This review no longer exists.',
      );
    });

    test('FORBIDDEN falls back to a clean access message', () {
      expect(
        mapReviewCallableError(appCode: 'FORBIDDEN'),
        "You don't have access to that review.",
      );
    });

    test('ADMIN_REQUIRED falls back to a clean admin message', () {
      expect(
        mapReviewCallableError(appCode: 'ADMIN_REQUIRED'),
        'Admin access is required for this action.',
      );
    });

    test('CANNOT_REPORT_OWN_REVIEW falls back to a clean message', () {
      expect(
        mapReviewCallableError(appCode: 'CANNOT_REPORT_OWN_REVIEW'),
        "You can't report your own review.",
      );
    });

    test('INVALID_REQUEST falls back to a generic retry message', () {
      expect(
        mapReviewCallableError(appCode: 'INVALID_REQUEST'),
        'Something went wrong with that request. Please try again.',
      );
    });

    test('INTERNAL falls back to a generic retry message', () {
      expect(
        mapReviewCallableError(appCode: 'INTERNAL'),
        'Something went wrong. Please try again.',
      );
    });

    test('a present server message is used verbatim over any fallback', () {
      expect(
        mapReviewCallableError(
          appCode: 'NOT_ELIGIBLE',
          message: 'Custom server-provided message.',
        ),
        'Custom server-provided message.',
      );
    });

    test('a blank server message is treated as absent', () {
      expect(
        mapReviewCallableError(appCode: 'NOT_ELIGIBLE', message: '   '),
        'You can only review products from a delivered order.',
      );
    });

    test('unavailable/deadline-exceeded grpc codes map to a network message '
        'even with no appCode', () {
      expect(
        mapReviewCallableError(appCode: null, grpcCode: 'unavailable'),
        'Network error. Please check your connection and try again.',
      );
      expect(
        mapReviewCallableError(appCode: null, grpcCode: 'deadline-exceeded'),
        'Network error. Please check your connection and try again.',
      );
    });

    test('an unrecognised appCode and grpcCode fall back to the generic '
        'retry message', () {
      expect(
        mapReviewCallableError(appCode: 'SOMETHING_NEW', grpcCode: 'unknown'),
        'Something went wrong. Please try again.',
      );
      expect(
        mapReviewCallableError(appCode: null, grpcCode: null),
        'Something went wrong. Please try again.',
      );
    });
  });
}
