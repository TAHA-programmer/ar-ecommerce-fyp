import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/review_report_reason.dart';
import 'package:twin_ar/features/reviews/models/review_sort_option.dart';
import 'package:twin_ar/features/reviews/models/review_validation.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';

void main() {
  group('eligibility (v1 §0 decision 1)', () {
    test('an ineligible user cannot submit - server-shaped rejection, not a '
        'silent no-op', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1');
      final err = await repo.submitReview(
        productId: 'p1',
        rating: 5,
        body: 'Loved this product, would buy again.',
      );
      expect(err, isNotNull);
      expect(await repo.isEligibleToReview('p1'), false);
      expect(await repo.myReviewFor('p1'), isNull);
    });

    test('marking eligible allows submission; marking ineligible again does '
        'not retroactively remove an existing review', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      expect(await repo.isEligibleToReview('p1'), true);

      final err = await repo.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'Good quality, fast delivery, would recommend.',
      );
      expect(err, isNull);

      repo.markIneligible('u1', 'p1');
      expect(await repo.myReviewFor('p1'), isNotNull);
    });
  });

  group('submitReview validation', () {
    late MockReviewsRepository repo;
    setUp(() {
      repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
    });

    test('rejects an out-of-range rating', () async {
      final err = await repo.submitReview(
        productId: 'p1',
        rating: 0,
        body: 'a' * 20,
      );
      expect(err, isNotNull);
    });

    test('rejects a title over the max length', () async {
      final err = await repo.submitReview(
        productId: 'p1',
        rating: 5,
        title: 'a' * (ReviewValidation.maxTitleLength + 1),
        body: 'a' * 20,
      );
      expect(err, isNotNull);
    });

    test('rejects a body shorter than the minimum', () async {
      final err = await repo.submitReview(
        productId: 'p1',
        rating: 5,
        body: 'too short',
      );
      expect(err, isNotNull);
    });

    test('rejects a body longer than the maximum', () async {
      final err = await repo.submitReview(
        productId: 'p1',
        rating: 5,
        body: 'a' * (ReviewValidation.maxBodyLength + 1),
      );
      expect(err, isNotNull);
    });

    test('accepts a valid submission', () async {
      final err = await repo.submitReview(
        productId: 'p1',
        rating: 5,
        title: 'Excellent',
        body: 'Exactly as described, five stars, will buy again soon.',
      );
      expect(err, isNull);
      final saved = await repo.myReviewFor('p1');
      expect(saved, isNotNull);
      expect(saved!.rating, 5);
      expect(saved.title, 'Excellent');
      expect(saved.hasBeenEdited, false);
    });
  });

  group('one review per user per product + repeat-purchase edit (v1 §0 '
      'decisions 2, 6)', () {
    test(
      'a second submission for the same product EDITS the same doc, '
      'never creates a second one - even across repeat "purchases"',
      () async {
        final fixedNow = DateTime(2026, 1, 1);
        final repo = MockReviewsRepository(
          currentUserId: 'u1',
          now: () => fixedNow,
        )..markEligible('u1', 'p1', orderId: 'order-1');

        await repo.submitReview(
          productId: 'p1',
          rating: 3,
          body: 'Decent, does the job, no complaints so far honestly.',
        );

        // Simulate a second delivered order for the SAME product.
        repo.markEligible('u1', 'p1', orderId: 'order-2');
        final err = await repo.submitReview(
          productId: 'p1',
          rating: 5,
          body: 'Bought a second one, even better than the first purchase.',
        );
        expect(err, isNull);

        final saved = await repo.myReviewFor('p1');
        expect(saved!.rating, 5);
        expect(saved.hasBeenEdited, true);
        expect(
          saved.orderId,
          'order-1',
          reason: 'the ORIGINAL qualifying order is preserved, not overwritten',
        );

        final stats = await repo.ratingStatsFor('p1');
        expect(
          stats.ratingCount,
          1,
          reason: 'an edit must never double-count as a second review',
        );
        expect(stats.ratingSum, 5);
      },
    );

    test('an edit within the 30-day window succeeds', () async {
      var now = DateTime(2026, 1, 1);
      final repo = MockReviewsRepository(currentUserId: 'u1', now: () => now)
        ..markEligible('u1', 'p1');
      await repo.submitReview(
        productId: 'p1',
        rating: 3,
        body: 'Initial thoughts after a couple of days of use.',
      );

      now = now.add(const Duration(days: 29));
      final err = await repo.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'Updating after two more weeks, holding up nicely.',
      );
      expect(err, isNull);
      expect((await repo.myReviewFor('p1'))!.rating, 4);
    });

    test(
      'an edit past the 30-day window is refused with a clear message',
      () async {
        var now = DateTime(2026, 1, 1);
        final repo = MockReviewsRepository(currentUserId: 'u1', now: () => now)
          ..markEligible('u1', 'p1');
        await repo.submitReview(
          productId: 'p1',
          rating: 3,
          body: 'Initial thoughts right after the order arrived today.',
        );

        now = now.add(const Duration(days: 31));
        final err = await repo.submitReview(
          productId: 'p1',
          rating: 1,
          body: 'Trying to change my review after more than a month.',
        );
        expect(err, isNotNull);
        expect(
          (await repo.myReviewFor('p1'))!.rating,
          3,
          reason: 'the refused edit must not have applied',
        );
      },
    );
  });

  group('rating aggregate transactional correctness (v1 §0 decision 15)', () {
    test('a create adds exactly once to sum/count/bucket', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await repo.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'Solid product overall, minor issues with packaging only.',
      );
      final stats = await repo.ratingStatsFor('p1');
      expect(stats.ratingCount, 1);
      expect(stats.ratingSum, 4);
      expect(stats.rating4Count, 1);
      expect(stats.averageRating, 4.0);
    });

    test('an edit reverses the OLD rating before applying the new one - '
        'never double-counted', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await repo.submitReview(
        productId: 'p1',
        rating: 2,
        body: 'Not great initially, hoping it improves with more use.',
      );
      await repo.submitReview(
        productId: 'p1',
        rating: 5,
        body: 'Actually it grew on me a lot, updating to five stars now.',
      );

      final stats = await repo.ratingStatsFor('p1');
      expect(stats.ratingCount, 1);
      expect(stats.ratingSum, 5);
      expect(stats.rating2Count, 0);
      expect(stats.rating5Count, 1);
    });

    test('deleting a review reverses its contribution entirely', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await repo.submitReview(
        productId: 'p1',
        rating: 3,
        body: 'An average product, nothing special but works fine.',
      );
      await repo.deleteReview('p1');

      final stats = await repo.ratingStatsFor('p1');
      expect(stats.ratingCount, 0);
      expect(stats.ratingSum, 0);
      expect(await repo.myReviewFor('p1'), isNull);
    });

    test('deleting a review that does not exist is a harmless no-op', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1');
      final err = await repo.deleteReview('does-not-exist');
      expect(err, isNull);
    });

    test('aggregates from different products never mix', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1')
        ..markEligible('u1', 'p2');
      await repo.submitReview(
        productId: 'p1',
        rating: 5,
        body: 'Five stars for this particular product, love it.',
      );
      await repo.submitReview(
        productId: 'p2',
        rating: 1,
        body: 'One star for this completely different product here.',
      );

      expect((await repo.ratingStatsFor('p1')).ratingSum, 5);
      expect((await repo.ratingStatsFor('p2')).ratingSum, 1);
    });
  });

  group('reporting (v1 §0 decisions 10, 11)', () {
    test('one report per user per review - a repeat report never double '
        'counts', () async {
      final repo = MockReviewsRepository(currentUserId: 'author')
        ..markEligible('author', 'p1');
      await repo.submitReview(
        productId: 'p1',
        rating: 3,
        body: 'A perfectly ordinary review of a perfectly ordinary item.',
      );
      final reviewId = (await repo.myReviewFor('p1'))!.id;

      repo.currentUserId = 'reporter-1';
      await repo.reportReview(
        reviewId: reviewId,
        reason: ReviewReportReason.spam,
      );
      await repo.reportReview(
        reviewId: reviewId,
        reason: ReviewReportReason.spam,
      );

      repo.currentUserId = 'author';
      final review = await repo.myReviewFor('p1');
      expect(review!.reportCount, 1);
    });

    test('reportCount reaching the threshold flags the review, without '
        'auto-hiding it', () async {
      final repo = MockReviewsRepository(currentUserId: 'author')
        ..markEligible('author', 'p1');
      await repo.submitReview(
        productId: 'p1',
        rating: 3,
        body: 'A perfectly ordinary review of a perfectly ordinary item.',
      );
      final reviewId = (await repo.myReviewFor('p1'))!.id;

      for (var i = 0; i < ReviewValidation.reportFlagThreshold; i++) {
        repo.currentUserId = 'reporter-$i';
        await repo.reportReview(
          reviewId: reviewId,
          reason: ReviewReportReason.spam,
        );
      }

      repo.currentUserId = 'author';
      final review = await repo.myReviewFor('p1');
      expect(review!.reportCount, ReviewValidation.reportFlagThreshold);
      expect(review.flaggedForReview, true);
      expect(
        (await repo.fetchReviews(productId: 'p1')).reviews,
        isNotEmpty,
        reason:
            'a flagged review is NOT auto-hidden - still publicly '
            'listed until an Admin acts',
      );
    });

    test(
      'reporting a review that does not exist returns a clean error',
      () async {
        final repo = MockReviewsRepository(currentUserId: 'u1');
        final err = await repo.reportReview(
          reviewId: 'nope',
          reason: ReviewReportReason.other,
        );
        expect(err, isNotNull);
      },
    );
  });

  group('fetchReviews pagination + sorting (v1 §0 decision 9)', () {
    late MockReviewsRepository repo;

    setUp(() async {
      repo = MockReviewsRepository(currentUserId: 'u');
      var t = DateTime(2026, 1, 1);
      repo.now = () => t;
      for (var i = 1; i <= 25; i++) {
        final uid = 'u$i';
        repo
          ..currentUserId = uid
          ..markEligible(uid, 'p1');
        await repo.submitReview(
          productId: 'p1',
          rating: (i % 5) + 1,
          body: 'Review number $i with enough characters to pass.',
        );
        t = t.add(const Duration(minutes: 1));
      }
      repo.currentUserId = 'u';
    });

    test(
      'default page size is respected and a cursor continues the list',
      () async {
        final page1 = await repo.fetchReviews(productId: 'p1');
        expect(page1.reviews.length, 10);
        expect(page1.hasMore, true);

        final page2 = await repo.fetchReviews(
          productId: 'p1',
          cursor: page1.nextCursor,
        );
        expect(page2.reviews.length, 10);

        final page3 = await repo.fetchReviews(
          productId: 'p1',
          cursor: page2.nextCursor,
        );
        expect(page3.reviews.length, 5);
        expect(page3.hasMore, false);

        final ids = {
          ...page1.reviews.map((r) => r.id),
          ...page2.reviews.map((r) => r.id),
          ...page3.reviews.map((r) => r.id),
        };
        expect(
          ids.length,
          25,
          reason: 'no duplicate or skipped review across pages',
        );
      },
    );

    test('newest-first is the default sort', () async {
      final page = await repo.fetchReviews(productId: 'p1');
      for (var i = 1; i < page.reviews.length; i++) {
        expect(
          page.reviews[i - 1].createdAt.isAfter(page.reviews[i].createdAt) ||
              page.reviews[i - 1].createdAt.isAtSameMomentAs(
                page.reviews[i].createdAt,
              ),
          true,
        );
      }
    });

    test('highestRating and lowestRating sort correctly', () async {
      final highest = await repo.fetchReviews(
        productId: 'p1',
        sort: ReviewSortOption.highestRating,
        pageSize: 25,
      );
      for (var i = 1; i < highest.reviews.length; i++) {
        expect(
          highest.reviews[i - 1].rating >= highest.reviews[i].rating,
          true,
        );
      }

      final lowest = await repo.fetchReviews(
        productId: 'p1',
        sort: ReviewSortOption.lowestRating,
        pageSize: 25,
      );
      for (var i = 1; i < lowest.reviews.length; i++) {
        expect(lowest.reviews[i - 1].rating <= lowest.reviews[i].rating, true);
      }
    });

    test(
      'a product with no reviews returns an empty page, not an error',
      () async {
        final page = await repo.fetchReviews(productId: 'nonexistent-product');
        expect(page.reviews, isEmpty);
        expect(page.hasMore, false);
      },
    );
  });

  group('authorDisplayName snapshot (v1 §0 decision 13 / §6)', () {
    test(
      'masks the configured display name onto the review at submission',
      () async {
        final repo = MockReviewsRepository(currentUserId: 'u1')
          ..markEligible('u1', 'p1')
          ..setDisplayName('u1', 'Ayesha Khan');

        await repo.submitReview(
          productId: 'p1',
          rating: 5,
          body: 'A review from an author with a configured display name.',
        );

        final review = await repo.myReviewFor('p1');
        expect(review!.authorDisplayName, 'Ayesha K.');
      },
    );

    test('falls back to the safe default for an unconfigured author', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');

      await repo.submitReview(
        productId: 'p1',
        rating: 5,
        body: 'A review from an author with no configured name at all.',
      );

      final review = await repo.myReviewFor('p1');
      expect(review!.authorDisplayName, 'Verified Buyer');
    });

    test(
      're-resolves on an edit, reflecting a since-changed display name',
      () async {
        final repo = MockReviewsRepository(currentUserId: 'u1')
          ..markEligible('u1', 'p1')
          ..setDisplayName('u1', 'Ayesha Raza');

        await repo.submitReview(
          productId: 'p1',
          rating: 3,
          body: 'Initial review body long enough to satisfy validation.',
        );
        expect((await repo.myReviewFor('p1'))!.authorDisplayName, 'Ayesha R.');

        repo.setDisplayName('u1', 'Ayesha Malik');
        await repo.submitReview(
          productId: 'p1',
          rating: 4,
          body: 'Edited review body long enough to satisfy validation too.',
        );
        expect((await repo.myReviewFor('p1'))!.authorDisplayName, 'Ayesha M.');
      },
    );
  });

  group('myReviews (v1 Stage 7 - Profile "My Reviews")', () {
    test('returns every review the current user wrote, across products, '
        'newest first', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1')
        ..markEligible('u1', 'p2');

      await repo.submitReview(
        productId: 'p1',
        rating: 3,
        body: 'The first review, written a little earlier than the other.',
      );
      repo.now = () => DateTime.now().add(const Duration(minutes: 1));
      await repo.submitReview(
        productId: 'p2',
        rating: 5,
        body: 'The second review, written a little later than the first.',
      );

      final mine = await repo.myReviews();
      expect(mine.length, 2);
      expect(mine.first.productId, 'p2'); // newest first
      expect(mine.last.productId, 'p1');
    });

    test('never returns another customer\'s reviews', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await repo.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A review written by the current user for this test case.',
      );

      repo.currentUserId = 'u2';
      final mine = await repo.myReviews();
      expect(mine, isEmpty);
    });

    test('an edit does not create a second entry in myReviews', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await repo.submitReview(
        productId: 'p1',
        rating: 2,
        body: 'Original review body long enough for validation here.',
      );
      await repo.submitReview(
        productId: 'p1',
        rating: 5,
        body: 'Edited review body long enough for validation too here.',
      );

      final mine = await repo.myReviews();
      expect(mine.length, 1);
      expect(mine.single.rating, 5);
    });

    test('a user with no reviews gets an empty list, not an error', () async {
      final repo = MockReviewsRepository(currentUserId: 'u1');
      expect(await repo.myReviews(), isEmpty);
    });
  });
}
