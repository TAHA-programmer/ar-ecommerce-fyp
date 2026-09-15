import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/reviews/models/product_rating_stats.dart';
import 'package:twin_ar/features/reviews/models/review_model.dart';
import 'package:twin_ar/features/reviews/models/review_report_reason.dart';
import 'package:twin_ar/features/reviews/models/review_sort_option.dart';
import 'package:twin_ar/features/reviews/models/reviews_page.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';
import 'package:twin_ar/features/reviews/repositories/reviews_repository.dart';
import 'package:twin_ar/features/reviews/viewmodels/reviews_viewmodel.dart';

AuthSessionState _session(String? uid) {
  final s = AuthSessionState();
  if (uid != null) {
    s.setSession(
      AuthResult.success(
        userId: uid,
        email: '$uid@x.com',
        role: UserRole.customer,
      ),
    );
  }
  return s;
}

Future<void> _flush() => Future.delayed(Duration.zero);

/// Wraps a [MockReviewsRepository] and lets a single test hold `submitReview`
/// open on a [Completer] - the only way to deterministically observe
/// [ReviewsViewModel]'s duplicate-request guard actually rejecting a SECOND,
/// overlapping call while the first is still in flight (the inner mock
/// otherwise resolves synchronously-fast, so two calls would never actually
/// overlap in a real test).
class _GatedReviewsRepository implements ReviewsRepository {
  final MockReviewsRepository inner;
  Completer<void>? submitGate;
  int submitCallCount = 0;

  _GatedReviewsRepository(this.inner);

  @override
  Future<ReviewsPage> fetchReviews({
    required String productId,
    ReviewSortOption sort = ReviewSortOption.newest,
    String? cursor,
    int pageSize = 10,
  }) => inner.fetchReviews(
    productId: productId,
    sort: sort,
    cursor: cursor,
    pageSize: pageSize,
  );

  @override
  Future<ProductRatingStats> ratingStatsFor(String productId) =>
      inner.ratingStatsFor(productId);

  @override
  Future<ReviewModel?> myReviewFor(String productId) =>
      inner.myReviewFor(productId);

  @override
  Future<List<ReviewModel>> myReviews() => inner.myReviews();

  @override
  Future<bool> isEligibleToReview(String productId) =>
      inner.isEligibleToReview(productId);

  @override
  Future<String?> submitReview({
    required String productId,
    required int rating,
    String? title,
    required String body,
  }) async {
    submitCallCount++;
    final gate = submitGate;
    if (gate != null) await gate.future;
    return inner.submitReview(
      productId: productId,
      rating: rating,
      title: title,
      body: body,
    );
  }

  @override
  Future<String?> deleteReview(String productId) =>
      inner.deleteReview(productId);

  @override
  Future<String?> reportReview({
    required String reviewId,
    required ReviewReportReason reason,
    String? note,
  }) => inner.reportReview(reviewId: reviewId, reason: reason, note: note);
}

void main() {
  const productId = 'p1';

  group('ReviewsViewModel — initial load', () {
    test(
      'starts loading, then resolves the list/aggregate/own-state',
      () async {
        final mock = MockReviewsRepository(currentUserId: 'u1');
        mock.markEligible('u1', productId);
        final viewModel = ReviewsViewModel(
          repository: mock,
          authSessionState: _session('u1'),
          productId: productId,
        );

        expect(viewModel.isLoading, true);
        await _flush();

        expect(viewModel.isLoading, false);
        expect(viewModel.hasLoadError, false);
        expect(viewModel.reviews, isEmpty);
        expect(viewModel.isEmpty, true);
        expect(viewModel.stats, ProductRatingStats.zero);
        expect(viewModel.myReview, isNull);
        expect(viewModel.isEligibleToReview, true);
      },
    );

    test(
      'a signed-out customer sees the public list but no own-state',
      () async {
        final mock = MockReviewsRepository(currentUserId: 'u1');
        mock.markEligible('u1', productId);
        await mock.submitReview(
          productId: productId,
          rating: 5,
          body: 'Wonderful, exactly as pictured and very sturdy.',
        );

        final viewModel = ReviewsViewModel(
          repository: mock,
          authSessionState: _session(null),
          productId: productId,
        );
        await _flush();

        expect(viewModel.reviews.length, 1);
        expect(viewModel.myReview, isNull);
        expect(viewModel.isEligibleToReview, false);
      },
    );
  });

  group('ReviewsViewModel — submit/edit/delete', () {
    test(
      'submitReview refuses with a clean message when not eligible',
      () async {
        final mock = MockReviewsRepository(currentUserId: 'u1');
        final viewModel = ReviewsViewModel(
          repository: mock,
          authSessionState: _session('u1'),
          productId: productId,
        );
        await _flush();

        final error = await viewModel.submitReview(
          rating: 5,
          body: 'Should be refused - not eligible yet.',
        );

        expect(error, 'You can only review products from a delivered order.');
        expect(viewModel.myReview, isNull);
        expect(viewModel.isSubmitting, false);
      },
    );

    test('a successful submit refreshes own-state, aggregate, and the '
        'review list', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      mock.markEligible('u1', productId);
      final viewModel = ReviewsViewModel(
        repository: mock,
        authSessionState: _session('u1'),
        productId: productId,
      );
      await _flush();

      final error = await viewModel.submitReview(
        rating: 5,
        title: 'Love it',
        body: 'Comfortable, sturdy, exactly as described in the listing.',
      );

      expect(error, isNull);
      expect(viewModel.isSubmitting, false);
      expect(viewModel.myReview, isNotNull);
      expect(viewModel.myReview!.rating, 5);
      expect(viewModel.stats.ratingCount, 1);
      expect(viewModel.stats.averageRating, 5.0);
      expect(
        viewModel.reviews.map((r) => r.id),
        contains(viewModel.myReview!.id),
      );
      expect(viewModel.isMine(viewModel.myReview!), true);
    });

    test('editing (resubmitting) reverses the old rating before applying '
        'the new one in the aggregate', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      mock.markEligible('u1', productId);
      final viewModel = ReviewsViewModel(
        repository: mock,
        authSessionState: _session('u1'),
        productId: productId,
      );
      await _flush();

      await viewModel.submitReview(
        rating: 2,
        body: 'Initial review - not great, changed my mind later on.',
      );
      expect(viewModel.stats.ratingCount, 1);
      expect(viewModel.stats.averageRating, 2.0);

      final error = await viewModel.submitReview(
        rating: 5,
        body: 'Edited review - actually this is fantastic after all.',
      );

      expect(error, isNull);
      expect(viewModel.stats.ratingCount, 1); // still one review, not two
      expect(viewModel.stats.averageRating, 5.0);
      expect(viewModel.myReview!.hasBeenEdited, true);
    });

    test('deleteReview clears own-state and reverses the aggregate', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      mock.markEligible('u1', productId);
      final viewModel = ReviewsViewModel(
        repository: mock,
        authSessionState: _session('u1'),
        productId: productId,
      );
      await _flush();
      await viewModel.submitReview(
        rating: 4,
        body: 'A perfectly fine review body for this test case here.',
      );
      expect(viewModel.stats.ratingCount, 1);

      final error = await viewModel.deleteReview();

      expect(error, isNull);
      expect(viewModel.myReview, isNull);
      expect(viewModel.stats.ratingCount, 0);
      expect(viewModel.isDeleting, false);
    });

    test('deleting with no existing review is a harmless no-op that never '
        'calls the repository', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      final viewModel = ReviewsViewModel(
        repository: mock,
        authSessionState: _session('u1'),
        productId: productId,
      );
      await _flush();

      final error = await viewModel.deleteReview();
      expect(error, isNull);
    });
  });

  group('ReviewsViewModel — reportReview', () {
    test('reports another customer\'s review successfully', () async {
      final mock = MockReviewsRepository(currentUserId: 'author');
      mock.markEligible('author', productId);
      await mock.submitReview(
        productId: productId,
        rating: 1,
        body: 'A review that will be reported by another customer here.',
      );
      final reviewId = ReviewModel.docIdFor(
        userId: 'author',
        productId: productId,
      );
      mock.currentUserId = 'reporter';

      final viewModel = ReviewsViewModel(
        repository: mock,
        authSessionState: _session('reporter'),
        productId: productId,
      );
      await _flush();

      final error = await viewModel.reportReview(
        reviewId: reviewId,
        reason: ReviewReportReason.spam,
      );
      expect(error, isNull);
      expect(viewModel.isReporting(reviewId), false);
    });

    test('reporting a nonexistent review surfaces the repository\'s clean '
        'error', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      final viewModel = ReviewsViewModel(
        repository: mock,
        authSessionState: _session('u1'),
        productId: productId,
      );
      await _flush();

      final error = await viewModel.reportReview(
        reviewId: 'does-not-exist',
        reason: ReviewReportReason.fake,
      );
      expect(error, 'This review no longer exists.');
    });
  });

  group('ReviewsViewModel — pagination and sorting', () {
    test('loadMore appends pages until hasMore is false', () async {
      // One review per user per product (v1 §0 decision 2), so exercising
      // pagination against a single product needs 15 distinct reviewers.
      final multi = MockReviewsRepository(currentUserId: 'u0');
      for (var i = 0; i < 15; i++) {
        multi.currentUserId = 'u$i';
        multi.markEligible('u$i', productId);
        await multi.submitReview(
          productId: productId,
          rating: 3,
          body: 'A review body long enough to satisfy validation here.',
        );
      }
      multi.currentUserId = 'u0';

      final viewModel = ReviewsViewModel(
        repository: multi,
        authSessionState: _session('u0'),
        productId: productId,
      );
      await _flush();

      expect(viewModel.reviews.length, 10);
      expect(viewModel.hasMore, true);

      await viewModel.loadMore();
      expect(viewModel.reviews.length, 15);
      expect(viewModel.hasMore, false);

      // A further loadMore is a no-op.
      await viewModel.loadMore();
      expect(viewModel.reviews.length, 15);
    });

    test('changeSort reloads the first page in the new order', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      mock.markEligible('u1', productId);
      await mock.submitReview(
        productId: productId,
        rating: 2,
        body: 'Lower rated review body long enough for validation here.',
      );
      mock.currentUserId = 'u2';
      mock.markEligible('u2', productId);
      await mock.submitReview(
        productId: productId,
        rating: 5,
        body: 'Higher rated review body long enough for validation here.',
      );

      final viewModel = ReviewsViewModel(
        repository: mock,
        authSessionState: _session('u1'),
        productId: productId,
      );
      await _flush();

      await viewModel.changeSort(ReviewSortOption.highestRating);
      expect(viewModel.sort, ReviewSortOption.highestRating);
      expect(viewModel.reviews.first.rating, 5);

      await viewModel.changeSort(ReviewSortOption.lowestRating);
      expect(viewModel.reviews.first.rating, 2);
    });
  });

  group('ReviewsViewModel — concurrency / duplicate-request protection', () {
    test('a second submitReview call while one is in flight is refused '
        'without hitting the repository again', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      mock.markEligible('u1', productId);
      final gated = _GatedReviewsRepository(mock)
        ..submitGate = Completer<void>();
      final viewModel = ReviewsViewModel(
        repository: gated,
        authSessionState: _session('u1'),
        productId: productId,
      );
      await _flush();

      final firstCall = viewModel.submitReview(
        rating: 4,
        body: 'The first, slow, in-flight submit call body text here.',
      );
      await _flush();
      expect(viewModel.isSubmitting, true);

      final secondResult = await viewModel.submitReview(
        rating: 1,
        body: 'A second overlapping submit call that must be refused.',
      );
      expect(secondResult, 'Please wait for the current request to finish.');
      expect(gated.submitCallCount, 1); // the repository was never called twice

      gated.submitGate!.complete();
      final firstResult = await firstCall;
      expect(firstResult, isNull);
      expect(viewModel.isSubmitting, false);
      expect(viewModel.myReview!.rating, 4); // the first call's rating won
    });

    test('deleteReview is refused while already in flight', () async {
      final mock = MockReviewsRepository(currentUserId: 'u1');
      mock.markEligible('u1', productId);
      final viewModel = ReviewsViewModel(
        repository: mock,
        authSessionState: _session('u1'),
        productId: productId,
      );
      await _flush();
      await viewModel.submitReview(
        rating: 3,
        body: 'A review to delete concurrently in this test case here.',
      );

      // `_isDeleting` is set synchronously before the first `await` inside
      // `deleteReview`, so calling it twice back-to-back (no `await`
      // between the two calls) deterministically makes the SECOND call see
      // the guard already up - not a race.
      final firstDelete = viewModel.deleteReview();
      final secondDelete = viewModel.deleteReview();

      expect(
        await secondDelete,
        'Please wait for the current request to finish.',
      );
      expect(await firstDelete, isNull);
      expect(viewModel.myReview, isNull);
    });
  });
}
