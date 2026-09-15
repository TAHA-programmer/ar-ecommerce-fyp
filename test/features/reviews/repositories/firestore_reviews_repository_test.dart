import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/reviews/models/product_rating_stats.dart';
import 'package:twin_ar/features/reviews/models/review_sort_option.dart';
import 'package:twin_ar/features/reviews/models/reviews_page.dart';
import 'package:twin_ar/features/reviews/repositories/firestore_reviews_repository.dart';

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

Future<void> _seedReview(
  FakeFirebaseFirestore firestore,
  String id, {
  required String productId,
  required String userId,
  required int rating,
  String status = 'published',
  required DateTime createdAt,
}) {
  return firestore.collection('reviews').doc(id).set({
    'productId': productId,
    'userId': userId,
    'authorDisplayName': 'Test User',
    'orderId': 'order-$userId-$productId',
    'rating': rating,
    'title': null,
    'body': 'A review body long enough to pass validation.',
    'status': status,
    'reportCount': 0,
    'flaggedForReview': false,
    'createdAt': Timestamp.fromDate(createdAt),
    'editedAt': null,
    'moderatedAt': null,
    'moderatedBy': null,
    'moderationReason': null,
  });
}

Future<void> _seedOrder(
  FakeFirebaseFirestore firestore,
  String id, {
  required String userId,
  required String orderStatus,
  required List<String> productIds,
}) {
  return firestore.collection('orders').doc(id).set({
    'userId': userId,
    'paymentId': 'pay-$id',
    'items': productIds
        .map(
          (pid) => {
            'productId': pid,
            'productName': 'Product $pid',
            'imagePath': 'assets/x.png',
            'imageSource': 'asset',
            'quantity': 1,
            'unitPrice': 100.0,
            'lineTotal': 100.0,
          },
        )
        .toList(),
    'orderDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
    'subtotal': 100.0,
    'deliveryFee': 0.0,
    'discount': 0.0,
    'total': 100.0,
    'paymentMethod': 'stripeCard',
    'paymentStatus': 'paid',
    'orderStatus': orderStatus,
    'deliveryAddress': <String, dynamic>{},
    'estimatedDeliveryStart': Timestamp.fromDate(DateTime(2026, 1, 3)),
    'estimatedDeliveryEnd': Timestamp.fromDate(DateTime(2026, 1, 5)),
  });
}

void main() {
  group('FirestoreReviewsRepository.fetchReviews', () {
    late FakeFirebaseFirestore firestore;

    setUp(() => firestore = FakeFirebaseFirestore());

    test('returns only published reviews for the given product, newest '
        'first', () async {
      await _seedReview(
        firestore,
        'u1_p1',
        productId: 'p1',
        userId: 'u1',
        rating: 5,
        createdAt: DateTime(2026, 1, 3),
      );
      await _seedReview(
        firestore,
        'u2_p1',
        productId: 'p1',
        userId: 'u2',
        rating: 3,
        createdAt: DateTime(2026, 1, 5),
      );
      await _seedReview(
        firestore,
        'u3_p1',
        productId: 'p1',
        userId: 'u3',
        rating: 1,
        status: 'hidden', // must never appear
        createdAt: DateTime(2026, 1, 6),
      );
      await _seedReview(
        firestore,
        'u1_p2',
        productId: 'p2', // a different product, must never appear
        userId: 'u1',
        rating: 4,
        createdAt: DateTime(2026, 1, 7),
      );

      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );
      final page = await repo.fetchReviews(productId: 'p1');

      expect(page.reviews.map((r) => r.id).toList(), ['u2_p1', 'u1_p1']);
      expect(page.hasMore, false);
    });

    test('paginates via cursor without skipping or repeating', () async {
      for (var i = 0; i < 5; i++) {
        await _seedReview(
          firestore,
          'u$i-p1',
          productId: 'p1',
          userId: 'u$i',
          rating: 3,
          createdAt: DateTime(2026, 1, 1 + i),
        );
      }
      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );

      final page1 = await repo.fetchReviews(productId: 'p1', pageSize: 2);
      expect(page1.reviews.length, 2);
      expect(page1.hasMore, true);

      final page2 = await repo.fetchReviews(
        productId: 'p1',
        pageSize: 2,
        cursor: page1.nextCursor,
      );
      expect(page2.reviews.length, 2);
      expect(page2.hasMore, true);

      final page3 = await repo.fetchReviews(
        productId: 'p1',
        pageSize: 2,
        cursor: page2.nextCursor,
      );
      expect(page3.reviews.length, 1);
      expect(page3.hasMore, false);

      final seenIds = [
        ...page1.reviews,
        ...page2.reviews,
        ...page3.reviews,
      ].map((r) => r.id).toSet();
      expect(seenIds.length, 5); // no duplicate, no skip
    });

    test('a cursor pointing at a since-deleted review ends the list rather '
        'than guessing', () async {
      await _seedReview(
        firestore,
        'u1-p1',
        productId: 'p1',
        userId: 'u1',
        rating: 3,
        createdAt: DateTime(2026, 1, 1),
      );
      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );
      final page = await repo.fetchReviews(
        productId: 'p1',
        cursor: 'does-not-exist',
      );
      expect(page, ReviewsPage.empty);
    });

    test('an empty product resolves to an empty page, not an error', () async {
      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );
      final page = await repo.fetchReviews(productId: 'no-reviews');
      expect(page.reviews, isEmpty);
      expect(page.hasMore, false);
    });

    test('highestRating/lowestRating sort within the bounded window, '
        'newest-first tiebreak', () async {
      await _seedReview(
        firestore,
        'a',
        productId: 'p1',
        userId: 'u1',
        rating: 3,
        createdAt: DateTime(2026, 1, 1),
      );
      await _seedReview(
        firestore,
        'b',
        productId: 'p1',
        userId: 'u2',
        rating: 5,
        createdAt: DateTime(2026, 1, 2),
      );
      await _seedReview(
        firestore,
        'c',
        productId: 'p1',
        userId: 'u3',
        rating: 1,
        createdAt: DateTime(2026, 1, 3),
      );
      await _seedReview(
        firestore,
        'd',
        productId: 'p1',
        userId: 'u4',
        rating: 5,
        createdAt: DateTime(2026, 1, 4), // newer 5-star, should sort before b
      );

      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );

      final highest = await repo.fetchReviews(
        productId: 'p1',
        sort: ReviewSortOption.highestRating,
      );
      expect(highest.reviews.map((r) => r.id).toList(), ['d', 'b', 'a', 'c']);

      final lowest = await repo.fetchReviews(
        productId: 'p1',
        sort: ReviewSortOption.lowestRating,
      );
      expect(lowest.reviews.map((r) => r.id).toList(), ['c', 'a', 'd', 'b']);
    });

    test('rating-sort pagination via an offset cursor covers every review '
        'exactly once', () async {
      for (var i = 0; i < 5; i++) {
        await _seedReview(
          firestore,
          'r$i',
          productId: 'p1',
          userId: 'u$i',
          rating: (i % 5) + 1,
          createdAt: DateTime(2026, 1, 1 + i),
        );
      }
      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );
      final page1 = await repo.fetchReviews(
        productId: 'p1',
        sort: ReviewSortOption.highestRating,
        pageSize: 3,
      );
      expect(page1.reviews.length, 3);
      expect(page1.hasMore, true);
      final page2 = await repo.fetchReviews(
        productId: 'p1',
        sort: ReviewSortOption.highestRating,
        pageSize: 3,
        cursor: page1.nextCursor,
      );
      expect(page2.reviews.length, 2);
      expect(page2.hasMore, false);
      final ids = [...page1.reviews, ...page2.reviews].map((r) => r.id).toSet();
      expect(ids.length, 5);
    });
  });

  group('FirestoreReviewsRepository.ratingStatsFor', () {
    late FakeFirebaseFirestore firestore;
    setUp(() => firestore = FakeFirebaseFirestore());

    test(
      'returns zero when the productStats document does not exist',
      () async {
        final repo = FirestoreReviewsRepository(
          _session(null),
          firestore: firestore,
        );
        expect(await repo.ratingStatsFor('missing'), ProductRatingStats.zero);
      },
    );

    test('maps the rating fields off an existing productStats document, '
        'ignoring unrelated fields', () async {
      await firestore.collection('productStats').doc('p1').set({
        'unitsSold': 10,
        'favoriteCount': 3,
        'ratingSum': 12,
        'ratingCount': 3,
        'averageRating': 4.0,
        'rating1Count': 0,
        'rating2Count': 0,
        'rating3Count': 0,
        'rating4Count': 1,
        'rating5Count': 2,
      });
      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );
      final stats = await repo.ratingStatsFor('p1');
      expect(stats.ratingCount, 3);
      expect(stats.averageRating, 4.0);
      expect(stats.rating5Count, 2);
    });
  });

  group('FirestoreReviewsRepository.myReviewFor', () {
    late FakeFirebaseFirestore firestore;
    setUp(() => firestore = FakeFirebaseFirestore());

    test('returns null when signed out', () async {
      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );
      expect(await repo.myReviewFor('p1'), isNull);
    });

    test('returns null when the signed-in customer has no review for this '
        'product', () async {
      final repo = FirestoreReviewsRepository(
        _session('u1'),
        firestore: firestore,
      );
      expect(await repo.myReviewFor('p1'), isNull);
    });

    test('returns the signed-in customer\'s own review by the deterministic '
        'doc id', () async {
      await _seedReview(
        firestore,
        'u1_p1',
        productId: 'p1',
        userId: 'u1',
        rating: 4,
        createdAt: DateTime(2026, 1, 1),
      );
      final repo = FirestoreReviewsRepository(
        _session('u1'),
        firestore: firestore,
      );
      final review = await repo.myReviewFor('p1');
      expect(review, isNotNull);
      expect(review!.id, 'u1_p1');
      expect(review.rating, 4);
    });

    test('never returns another customer\'s review', () async {
      await _seedReview(
        firestore,
        'u2_p1',
        productId: 'p1',
        userId: 'u2',
        rating: 5,
        createdAt: DateTime(2026, 1, 1),
      );
      final repo = FirestoreReviewsRepository(
        _session('u1'),
        firestore: firestore,
      );
      expect(await repo.myReviewFor('p1'), isNull);
    });
  });

  group('FirestoreReviewsRepository.isEligibleToReview', () {
    late FakeFirebaseFirestore firestore;
    setUp(() => firestore = FakeFirebaseFirestore());

    test('fails closed to false when signed out', () async {
      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );
      expect(await repo.isEligibleToReview('p1'), false);
    });

    test('false when the customer has no orders at all', () async {
      final repo = FirestoreReviewsRepository(
        _session('u1'),
        firestore: firestore,
      );
      expect(await repo.isEligibleToReview('p1'), false);
    });

    test('false when the order is not yet delivered', () async {
      await _seedOrder(
        firestore,
        'o1',
        userId: 'u1',
        orderStatus: 'shipped',
        productIds: ['p1'],
      );
      final repo = FirestoreReviewsRepository(
        _session('u1'),
        firestore: firestore,
      );
      expect(await repo.isEligibleToReview('p1'), false);
    });

    test(
      'false when a delivered order exists but for a different product',
      () async {
        await _seedOrder(
          firestore,
          'o1',
          userId: 'u1',
          orderStatus: 'delivered',
          productIds: ['p2'],
        );
        final repo = FirestoreReviewsRepository(
          _session('u1'),
          firestore: firestore,
        );
        expect(await repo.isEligibleToReview('p1'), false);
      },
    );

    test(
      'false for another customer\'s delivered order of the same product',
      () async {
        await _seedOrder(
          firestore,
          'o1',
          userId: 'someone-else',
          orderStatus: 'delivered',
          productIds: ['p1'],
        );
        final repo = FirestoreReviewsRepository(
          _session('u1'),
          firestore: firestore,
        );
        expect(await repo.isEligibleToReview('p1'), false);
      },
    );

    test('true when the customer has a delivered order containing the '
        'product', () async {
      await _seedOrder(
        firestore,
        'o1',
        userId: 'u1',
        orderStatus: 'pending',
        productIds: ['p9'],
      );
      await _seedOrder(
        firestore,
        'o2',
        userId: 'u1',
        orderStatus: 'delivered',
        productIds: ['p1', 'p3'],
      );
      final repo = FirestoreReviewsRepository(
        _session('u1'),
        firestore: firestore,
      );
      expect(await repo.isEligibleToReview('p1'), true);
    });
  });

  group('FirestoreReviewsRepository.myReviews', () {
    late FakeFirebaseFirestore firestore;
    setUp(() => firestore = FakeFirebaseFirestore());

    test('fails closed to an empty list when signed out', () async {
      final repo = FirestoreReviewsRepository(
        _session(null),
        firestore: firestore,
      );
      expect(await repo.myReviews(), isEmpty);
    });

    test('returns every review the signed-in customer wrote, across '
        'products, newest first - and never another customer\'s', () async {
      await _seedReview(
        firestore,
        'u1_p1',
        productId: 'p1',
        userId: 'u1',
        rating: 3,
        createdAt: DateTime(2026, 1, 1),
      );
      await _seedReview(
        firestore,
        'u1_p2',
        productId: 'p2',
        userId: 'u1',
        rating: 5,
        createdAt: DateTime(2026, 1, 5),
      );
      await _seedReview(
        firestore,
        'u2_p3',
        productId: 'p3',
        userId: 'u2', // a different customer - must never appear
        rating: 4,
        createdAt: DateTime(2026, 1, 6),
      );

      final repo = FirestoreReviewsRepository(
        _session('u1'),
        firestore: firestore,
      );
      final mine = await repo.myReviews();

      expect(mine.map((r) => r.id).toList(), ['u1_p2', 'u1_p1']);
    });

    test('includes a review regardless of its moderation status - the '
        'author can always see their own review', () async {
      await _seedReview(
        firestore,
        'u1_p1',
        productId: 'p1',
        userId: 'u1',
        rating: 1,
        status: 'hidden',
        createdAt: DateTime(2026, 1, 1),
      );
      final repo = FirestoreReviewsRepository(
        _session('u1'),
        firestore: firestore,
      );
      final mine = await repo.myReviews();
      expect(mine, hasLength(1));
    });

    test(
      'a customer with no reviews gets an empty list, not an error',
      () async {
        final repo = FirestoreReviewsRepository(
          _session('u1'),
          firestore: firestore,
        );
        expect(await repo.myReviews(), isEmpty);
      },
    );
  });

  group('Firestore composite-index requirements (v1 §5)', () {
    // Neither `fake_cloud_firestore` (used throughout this file) nor the
    // real local Firestore Emulator enforce Firestore's composite-index
    // requirements - that is a documented limitation of BOTH tools, not
    // something a differently-written Dart/Node test could route around.
    // Only production Firestore itself rejects an under-indexed query at
    // query time. So instead of (falsely) claiming index adequacy from a
    // passing `fetchReviews` call against the fake, these tests verify the
    // actual INVARIANT that makes a missing index impossible today: every
    // sort option's query only ever orders by `createdAt` (the ONE indexed
    // field) and does any rating-order sorting in Dart, never in the
    // Firestore query itself. If a future change ever adds a real
    // `.orderBy('rating', ...)` call, the source-scan test below fails
    // immediately, forcing a deliberate index (`firestore.indexes.json`)
    // and rules-emulator update alongside it - never a silent gap that
    // only surfaces as a production `failed-precondition` error.
    final repositorySource = File(
      'lib/features/reviews/repositories/firestore_reviews_repository.dart',
    ).readAsStringSync();

    test('never issues a Firestore query ordered by rating - highest/lowest '
        'sort is always done in Dart over the createdAt-ordered window, so '
        'no composite index beyond the existing one is ever required', () {
      expect(
        repositorySource.contains("orderBy('rating'"),
        false,
        reason:
            'A `.orderBy(\'rating\', ...)` call would require a NEW '
            'composite index (e.g. productId+status+rating) that is not '
            'declared in firestore.indexes.json - see this group\'s header '
            'comment. If this test now fails, a genuine indexed rating-sort '
            'is being added: declare the matching composite index(es) '
            'first, then update this test to reflect the new, deliberate '
            'contract.',
      );
      // Every query in this file orders exclusively by the one indexed
      // field - confirms the claim above is about what's actually shipped,
      // not just the absence of the one string above.
      expect(repositorySource.contains("orderBy('createdAt'"), true);
    });

    test('firestore.indexes.json declares EXACTLY the one composite index '
        'every query in this repository actually needs - '
        'reviews(productId ASC, status ASC, createdAt DESC)', () {
      final raw = File('firestore.indexes.json').readAsStringSync();
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final indexes = (decoded['indexes'] as List).cast<Map<String, dynamic>>();
      final reviewIndexes = indexes
          .where((i) => i['collectionGroup'] == 'reviews')
          .toList();

      expect(
        reviewIndexes.length,
        1,
        reason:
            'Exactly one composite index on `reviews` is needed today - if '
            'this now fails because a new one was added, confirm it is for '
            'a genuinely new indexed query (not a leftover/speculative '
            'entry) before updating this count.',
      );
      final fields = (reviewIndexes.single['fields'] as List)
          .cast<Map<String, dynamic>>();
      expect(fields.length, 3);
      expect(fields[0]['fieldPath'], 'productId');
      expect(fields[0]['order'], 'ASCENDING');
      expect(fields[1]['fieldPath'], 'status');
      expect(fields[1]['order'], 'ASCENDING');
      expect(fields[2]['fieldPath'], 'createdAt');
      expect(fields[2]['order'], 'DESCENDING');
    });

    test('every fetchReviews query (all three sort options) filters by '
        'productId + published status only - matching the declared '
        'index\'s equality-filter prefix exactly', () {
      expect(repositorySource.contains("where('productId', isEqualTo:"), true);
      expect(repositorySource.contains("where('status', isEqualTo:"), true);
    });
  });

  group(
    'deleteReview callable response type (2026-09 physical-test finding)',
    () {
      // `deleteReview` is a genuine `httpsCallable` invocation, so its actual
      // wiring can't be exercised without a `cloud_functions` test double
      // (this codebase has none - see this file's/FirestoreReviewsRepository's
      // own doc comments for why). But the exact bug physical testing found IS
      // provable from the source alone: `deleteReviewHandler` (`deleteReview.ts`)
      // returns `Promise<void>` - no payload - while `HttpsCallableResult<T>`
      // (`cloud_functions` 6.4.0) assigns the raw platform response straight
      // into a `final T _data` field with no null-check. Requesting
      // `.call<Map<String, dynamic>>(...)` on a callable that returns nothing
      // throws a `TypeError` (`null` is not a `Map<String, dynamic>`) - NOT a
      // `FirebaseFunctionsException` - client-side, AFTER the Firestore
      // transaction already committed, so the customer saw "Network error..."
      // on every successful delete. `submitReview`/`reportReview`/
      // `moderateReview` never had this bug - their handlers all return a real
      // result object. This test locks the fix (`<dynamic>`, never
      // `<Map<String, dynamic>>`, on the delete call specifically) as a
      // source-level invariant - the same "can't verify behavior directly, so
      // verify the shape that makes the bug impossible" approach already used
      // by the composite-index group above.
      final repositorySource = File(
        'lib/features/reviews/repositories/firestore_reviews_repository.dart',
      ).readAsStringSync();

      test('the deleteReview callable is never invoked with '
          '.call<Map<String, dynamic>>(...) - deleteReviewHandler returns no '
          'payload, so casting its response to a Map throws client-side on '
          'every successful delete', () {
        final deleteMethodStart = repositorySource.indexOf(
          'Future<String?> deleteReview(',
        );
        expect(deleteMethodStart, greaterThan(-1));
        final deleteMethodBody = repositorySource.substring(
          deleteMethodStart,
          repositorySource.indexOf(
            "Future<String?> reportReview(",
            deleteMethodStart,
          ),
        );
        expect(
          deleteMethodBody.contains('.call<Map<String, dynamic>>'),
          false,
          reason:
              'deleteReview must never request a Map<String, dynamic> '
              'response - deleteReviewHandler returns Promise<void>, so that '
              'response is null and the cast throws, masking a successful '
              'delete as a "Network error" (the exact 2026-09 physical-test '
              'finding). Use .call<dynamic>(...) instead.',
        );
        expect(deleteMethodBody.contains('.call<dynamic>'), true);
      });

      test('submitReview/reportReview genuinely DO return a payload, so they '
          'correctly keep requesting Map<String, dynamic> - this bug was '
          'never generic to every callable, only to the one with no return '
          'value', () {
        expect(repositorySource.contains('.call<Map<String, dynamic>>'), true);
      });
    },
  );
}
