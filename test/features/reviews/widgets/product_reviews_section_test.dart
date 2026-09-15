import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
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
import 'package:twin_ar/features/reviews/widgets/product_reviews_section.dart';

const _productId = 'p1';

/// Always fails `fetchReviews`/`ratingStatsFor` for the first [failTimes]
/// calls (each method counted separately), then delegates to [inner] - lets
/// a test exercise both the error state AND a genuine Retry recovery.
class _FlakyReviewsRepository implements ReviewsRepository {
  final ReviewsRepository inner;
  int failTimes;

  _FlakyReviewsRepository(this.inner, {this.failTimes = 1});

  @override
  Future<ReviewsPage> fetchReviews({
    required String productId,
    ReviewSortOption sort = ReviewSortOption.newest,
    String? cursor,
    int pageSize = 10,
  }) {
    if (failTimes > 0) {
      failTimes--;
      throw Exception('simulated failure');
    }
    return inner.fetchReviews(
      productId: productId,
      sort: sort,
      cursor: cursor,
      pageSize: pageSize,
    );
  }

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
  }) => inner.submitReview(
    productId: productId,
    rating: rating,
    title: title,
    body: body,
  );

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

Widget _createWidget(
  ReviewsRepository repository, {
  AuthSessionState? authSessionState,
}) {
  return MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: ChangeNotifierProvider<ReviewsViewModel>(
          create: (_) => ReviewsViewModel(
            repository: repository,
            authSessionState: authSessionState ?? AuthSessionState(),
            productId: _productId,
          ),
          child: const ProductReviewsSection(productTitle: 'Test Product'),
        ),
      ),
    ),
  );
}

/// Submits [count] distinct-user reviews for [_productId] via [repo],
/// oldest first (each one microsecond apart so `newest` sort is
/// deterministic).
Future<void> _seedReviews(
  MockReviewsRepository repo,
  int count, {
  int Function(int index)? ratingFor,
}) async {
  final base = DateTime(2026, 1, 1);
  for (var i = 0; i < count; i++) {
    repo.currentUserId = 'user$i';
    repo.now = () => base.add(Duration(minutes: i));
    repo.markEligible('user$i', _productId);
    await repo.submitReview(
      productId: _productId,
      rating: ratingFor != null ? ratingFor(i) : 3,
      body: 'Review body number $i, long enough to satisfy validation.',
    );
  }
}

void main() {
  group('ProductReviewsSection', () {
    testWidgets('shows a loading indicator on the very first frame', (
      tester,
    ) async {
      await tester.pumpWidget(_createWidget(MockReviewsRepository()));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
    });

    testWidgets('shows the honest empty state for a product with no '
        'reviews', (tester) async {
      await tester.pumpWidget(_createWidget(MockReviewsRepository()));
      await tester.pumpAndSettle();

      expect(find.text('No reviews yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('shows the summary, distribution, sort control, and every '
        'review once loaded', (tester) async {
      final repo = MockReviewsRepository();
      await _seedReviews(repo, 3, ratingFor: (_) => 5);

      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('5.0'), findsOneWidget); // average
      expect(find.text('3 reviews'), findsOneWidget);
      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Highest Rated'), findsOneWidget);
      expect(find.text('Lowest Rated'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(
          find.text(
            'Review body number $i, long enough to satisfy '
            'validation.',
          ),
          findsOneWidget,
        );
      }
    });

    testWidgets('shows an error state with Retry, and Retry recovers once '
        'the underlying read succeeds', (tester) async {
      final good = MockReviewsRepository();
      await _seedReviews(good, 1);
      final flaky = _FlakyReviewsRepository(good, failTimes: 1);

      await tester.pumpWidget(_createWidget(flaky));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load reviews."), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.text('No reviews yet'), findsNothing);

      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text("Couldn't load reviews."), findsNothing);
      expect(
        find.text(
          'Review body number 0, long enough to satisfy '
          'validation.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('paginates via "Load more reviews"', (tester) async {
      final repo = MockReviewsRepository();
      await _seedReviews(repo, 15);

      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('Load more reviews'), findsOneWidget);
      // Review 0 was submitted earliest, so under the default newest-first
      // sort it's the OLDEST of the 15 - it belongs on page 2, not page 1.
      expect(
        find.text(
          'Review body number 0, long enough to satisfy '
          'validation.',
        ),
        findsNothing,
      );

      await tester.ensureVisible(find.text('Load more reviews'));
      await tester.tap(find.text('Load more reviews'));
      await tester.pumpAndSettle();

      expect(find.text('Load more reviews'), findsNothing);
      expect(
        find.text(
          'Review body number 0, long enough to satisfy '
          'validation.',
        ),
        findsOneWidget,
      );
    });

    testWidgets('changing sort reorders the visible list', (tester) async {
      final repo = MockReviewsRepository();
      repo.currentUserId = 'low';
      repo.markEligible('low', _productId);
      await repo.submitReview(
        productId: _productId,
        rating: 1,
        body: 'A low rated review long enough for validation to pass.',
      );
      repo.currentUserId = 'high';
      repo.markEligible('high', _productId);
      await repo.submitReview(
        productId: _productId,
        rating: 5,
        body: 'A high rated review long enough for validation to pass.',
      );

      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Highest Rated'));
      await tester.pumpAndSettle();

      final highIndex = tester
          .getTopLeft(
            find.text(
              'A high rated review long enough for validation to pass.',
            ),
          )
          .dy;
      final lowIndex = tester
          .getTopLeft(
            find.text('A low rated review long enough for validation to pass.'),
          )
          .dy;
      expect(highIndex, lessThan(lowIndex));
    });

    testWidgets('shows the masked author name the repository stamped onto '
        'the review, never the raw profile name', (tester) async {
      // The masked name is a server-computed snapshot ON the review itself
      // (see `ReviewModel.authorDisplayName`'s doc comment for why - a
      // client can never look up another customer's profile to resolve
      // this). `MockReviewsRepository.setDisplayName` mirrors the real
      // `submitReview` callable's own masking at submission time.
      final repo = MockReviewsRepository(currentUserId: 'u1');
      repo.setDisplayName('u1', 'Ayesha Khan');
      repo.markEligible('u1', _productId);
      await repo.submitReview(
        productId: _productId,
        rating: 5,
        body: 'A review whose author has a configured display name here.',
      );

      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('Ayesha K.'), findsOneWidget);
      expect(find.text('Ayesha Khan'), findsNothing); // never the raw name
    });

    testWidgets('falls back to the safe default name for a review with no '
        'configured display name', (tester) async {
      final repo = MockReviewsRepository(currentUserId: 'u1');
      repo.markEligible('u1', _productId);
      await repo.submitReview(
        productId: _productId,
        rating: 5,
        body: 'A review with no configured display name at all here.',
      );

      await tester.pumpWidget(_createWidget(repo));
      await tester.pumpAndSettle();

      expect(find.text('Verified Buyer'), findsOneWidget);
    });
  });

  group('ProductReviewsSection — report', () {
    AuthSessionState signedInAs(String uid) {
      final state = AuthSessionState();
      state.setSession(
        AuthResult.success(
          userId: uid,
          email: '$uid@x.com',
          role: UserRole.customer,
        ),
      );
      return state;
    }

    testWidgets('never shows Report on the signed-in customer\'s OWN review', (
      tester,
    ) async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', _productId);
      await repo.submitReview(
        productId: _productId,
        rating: 5,
        body: 'A review written by the signed-in customer themselves.',
      );

      await tester.pumpWidget(
        _createWidget(repo, authSessionState: signedInAs('u1')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Report'), findsNothing);
    });

    testWidgets('shows Report on another customer\'s review, and submitting '
        'it calls the repository', (tester) async {
      final repo = MockReviewsRepository(currentUserId: 'other')
        ..markEligible('other', _productId);
      await repo.submitReview(
        productId: _productId,
        rating: 3,
        body: 'A review written by a DIFFERENT customer than the viewer.',
      );

      await tester.pumpWidget(
        _createWidget(repo, authSessionState: signedInAs('viewer')),
      );
      await tester.pumpAndSettle();

      expect(find.text('Report'), findsOneWidget);
      await tester.tap(find.text('Report'));
      await tester.pumpAndSettle();

      expect(find.text('Report this review'), findsOneWidget);
      await tester.tap(find.byKey(const Key('review_report_submit_button')));
      await tester.pumpAndSettle();

      expect(find.text("Thanks - we'll take a look."), findsOneWidget);
      // AppToast holds a static auto-dismiss Timer - drain it before the
      // test ends (mirrors the established pattern in `profile_view_test`/
      // `write_review_view_test`), else teardown fails with "A Timer is
      // still pending".
      await tester.pump(const Duration(seconds: 4));
    });
  });
}
