import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import '../../../core/data/order_firestore_mapper.dart';
import '../../../core/models/order/order_model.dart';
import '../models/product_rating_stats.dart';
import '../models/review_model.dart';
import '../models/review_report_reason.dart';
import '../models/review_sort_option.dart';
import '../models/review_status.dart';
import '../models/reviews_page.dart';
import 'review_callable_errors.dart';
import 'review_firestore_mapper.dart';
import 'reviews_repository.dart';

/// Real [ReviewsRepository]: Firestore reads (the rules-allowed published
/// list / rating aggregate / own review / eligibility-display query) +
/// `submitReview`/`deleteReview`/`reportReview` callables (Cloud Functions,
/// `us-central1`) for every mutation - mirrors [FirebaseVirtualTryOnService]'s
/// established "direct Firestore reads, callable-only writes" shape for a
/// domain where `firestore.rules` denies every direct client write
/// (v1 §0 decision 14).
///
/// `submitReview`/`deleteReview`/`reportReview`/`moderateReview` are NOT
/// deployed yet (Stage 2/3, `TECH PASSED` but local-only) - every call this
/// repository makes will fail until Stage 10's explicit, developer-approved
/// deploy. That is expected and does not change this repository's contract:
/// every mutating method still returns a clean, `AppToast`-ready message
/// rather than throwing.
///
/// Deliberately does NOT implement admin moderation (`moderateReview`) -
/// that action is admin-only and belongs to the dedicated Admin Reviews
/// screen (Stage 8), which - matching this codebase's established
/// customer/admin repository split (e.g. `ProductDetailsRepository` vs. the
/// separate admin product-management data path) - will get its own
/// admin-scoped repository rather than widening this customer-facing
/// contract.
class FirestoreReviewsRepository implements ReviewsRepository {
  static const String _functionsRegion = 'us-central1';

  /// Ratings/Reviews v1 §5 - CONFIRMED, not merely deferred (re-audited
  /// during Stage 7's index-support review): `reviews (productId ASC,
  /// status ASC, createdAt DESC)` is the ONLY composite index this
  /// repository needs for ALL THREE sort options exposed by the UI,
  /// because `highestRating`/`lowestRating` NEVER ask Firestore to order by
  /// `rating` - they re-sort a bounded, `createdAt`-ordered window (fetched
  /// via that SAME existing index) in memory. This is a deliberate,
  /// permanent design choice, not a placeholder waiting for a rating-order
  /// index to be added later - see
  /// `test/features/reviews/repositories/firestore_reviews_repository_test.dart`'s
  /// "Firestore composite-index requirements" group, which fails loudly if
  /// a future change ever makes the rating field itself the Firestore
  /// query's own sort key without a deliberately-added matching index
  /// alongside it. The
  /// trade-off this choice makes: a product with more than
  /// [_ratingSortWindow] published reviews will not have every review
  /// considered for a rating-sorted page - an accepted, documented
  /// limitation, not a silent bug.
  static const int _ratingSortWindow = 500;

  final AuthSessionState _authSessionState;
  final FirebaseFirestore _firestore;
  final FirebaseFunctions? _injectedFunctions;

  FirestoreReviewsRepository(
    this._authSessionState, {
    FirebaseFirestore? firestore,
    FirebaseFunctions? functions,
  }) : _firestore = firestore ?? FirebaseFirestore.instance,
       _injectedFunctions = functions;

  FirebaseFunctions get _functions =>
      _injectedFunctions ??
      FirebaseFunctions.instanceFor(region: _functionsRegion);

  String? get _uid =>
      _authSessionState.isAuthenticated ? _authSessionState.userId : null;

  CollectionReference<Map<String, dynamic>> get _reviewsCollection =>
      _firestore.collection('reviews');

  CollectionReference<Map<String, dynamic>> get _ordersCollection =>
      _firestore.collection('orders');

  DocumentReference<Map<String, dynamic>> _productStatsDoc(String productId) =>
      _firestore.collection('productStats').doc(productId);

  Query<Map<String, dynamic>> _publishedQuery(String productId) =>
      _reviewsCollection
          .where('productId', isEqualTo: productId)
          .where('status', isEqualTo: ReviewStatus.published.wireValue);

  @override
  Future<ReviewsPage> fetchReviews({
    required String productId,
    ReviewSortOption sort = ReviewSortOption.newest,
    String? cursor,
    int pageSize = 10,
  }) async {
    try {
      if (sort == ReviewSortOption.newest) {
        return await _fetchNewestPage(productId, cursor, pageSize);
      }
      return await _fetchRatingSortedPage(productId, sort, cursor, pageSize);
    } catch (_) {
      return ReviewsPage.empty;
    }
  }

  Future<ReviewsPage> _fetchNewestPage(
    String productId,
    String? cursor,
    int pageSize,
  ) async {
    var query = _publishedQuery(
      productId,
    ).orderBy('createdAt', descending: true);

    if (cursor != null) {
      final anchor = await _reviewsCollection.doc(cursor).get();
      if (!anchor.exists) {
        // The anchor review is gone (deleted, or moderated out of the
        // published set) between pages - nothing safe to resume from.
        // Ending the list here is honest; it can never skip or repeat a
        // review the way guessing an offset could.
        return ReviewsPage.empty;
      }
      query = query.startAfterDocument(anchor);
    }

    // The cursor MUST be applied before `limit` - some Firestore query
    // implementations resolve chained operations strictly in call order, so
    // `limit` before a cursor would truncate the candidate set first and
    // then search for the anchor inside that already-truncated page
    // (finding it at/near the end and returning nothing).
    query = query.limit(pageSize);

    final snapshot = await query.get();
    final reviews = snapshot.docs
        .map((d) => reviewModelFromFirestore(d.id, d.data()))
        .toList(growable: false);
    final next = reviews.length == pageSize ? reviews.last.id : null;
    return ReviewsPage(reviews: reviews, nextCursor: next);
  }

  Future<ReviewsPage> _fetchRatingSortedPage(
    String productId,
    ReviewSortOption sort,
    String? cursor,
    int pageSize,
  ) async {
    final snapshot = await _publishedQuery(
      productId,
    ).orderBy('createdAt', descending: true).limit(_ratingSortWindow).get();

    final all = snapshot.docs
        .map((d) => reviewModelFromFirestore(d.id, d.data()))
        .toList();
    all.sort(
      sort == ReviewSortOption.highestRating
          ? (a, b) => b.rating != a.rating
                ? b.rating.compareTo(a.rating)
                : b.createdAt.compareTo(a.createdAt)
          : (a, b) => a.rating != b.rating
                ? a.rating.compareTo(b.rating)
                : b.createdAt.compareTo(a.createdAt),
    );

    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    if (start < 0 || start > all.length) return ReviewsPage.empty;
    final end = (start + pageSize).clamp(0, all.length);
    final page = all.sublist(start, end);
    final next = end < all.length ? '$end' : null;
    return ReviewsPage(reviews: page, nextCursor: next);
  }

  @override
  Future<ProductRatingStats> ratingStatsFor(String productId) async {
    try {
      final doc = await _productStatsDoc(productId).get();
      return productRatingStatsFromFirestore(doc.data());
    } catch (_) {
      return ProductRatingStats.zero;
    }
  }

  @override
  Future<ReviewModel?> myReviewFor(String productId) async {
    final uid = _uid;
    if (uid == null) return null;
    try {
      final id = ReviewModel.docIdFor(userId: uid, productId: productId);
      final doc = await _reviewsCollection.doc(id).get();
      final data = doc.data();
      if (data == null) return null;
      return reviewModelFromFirestore(doc.id, data);
    } catch (_) {
      return null;
    }
  }

  /// Bounds the "My Reviews" read - a generous cap for a real customer's
  /// review history; a single-field `where` (see [myReviews]) has no
  /// server-side sort to page through cheaply, so this is a flat limit
  /// rather than true pagination, matching `RecentlyViewedRepository`'s
  /// same "bounded read, no pagination needed at this scale" convention.
  static const int _myReviewsLimit = 200;

  @override
  Future<List<ReviewModel>> myReviews() async {
    final uid = _uid;
    if (uid == null) return const [];
    try {
      // Single-field `where` (auto-indexed, no composite index) - the SAME
      // strategy as `isEligibleToReview` below and
      // `StripeCheckoutPaymentService.recentlyPurchasedLines` - sorting
      // newest-first happens in Dart, never as a Firestore `orderBy`
      // combined with this filter, so this can never require a composite
      // index that doesn't exist (see the "Firestore composite-index
      // requirements" test group for the equivalent guard on
      // `fetchReviews`).
      final snapshot = await _reviewsCollection
          .where('userId', isEqualTo: uid)
          .limit(_myReviewsLimit)
          .get();
      final reviews = snapshot.docs
          .map((d) => reviewModelFromFirestore(d.id, d.data()))
          .toList();
      reviews.sort((a, b) => b.createdAt.compareTo(a.createdAt));
      return reviews;
    } catch (_) {
      return const [];
    }
  }

  @override
  Future<bool> isEligibleToReview(String productId) async {
    final uid = _uid;
    if (uid == null) return false;
    try {
      // Single-field `where` (auto-indexed, no composite) + an in-memory
      // scan - the exact strategy `24_RATINGS_REVIEWS_FEEDBACK_PLAN.md` §1
      // specifies, mirroring `StripeCheckoutPaymentService
      // .recentlyPurchasedLines`'s established precedent. Display-only: the
      // real gate is `submitReview`'s own server-side re-verification via
      // the Admin SDK.
      final snapshot = await _ordersCollection
          .where('userId', isEqualTo: uid)
          .get();
      for (final doc in snapshot.docs) {
        final order = orderModelFromFirestore(doc.id, doc.data());
        if (order.orderStatus == OrderStatus.delivered &&
            order.items.any((item) => item.productId == productId)) {
          return true;
        }
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> submitReview({
    required String productId,
    required int rating,
    String? title,
    required String body,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'submitReview',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'productId': productId,
        'rating': rating,
        'title': title,
        'body': body,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return mapReviewCallableError(
        appCode: _appCodeOf(e),
        grpcCode: e.code,
        message: e.message,
      );
    } catch (_) {
      return 'Network error. Please check your connection and try again.';
    }
  }

  @override
  Future<String?> deleteReview(String productId) async {
    try {
      final callable = _functions.httpsCallable(
        'deleteReview',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      // `deleteReviewHandler` returns `Promise<void>` (see `deleteReview.ts`)
      // - the callable response has no payload. `<dynamic>` (never
      // `<Map<String, dynamic>>`) is REQUIRED here: `HttpsCallableResult<T>`
      // assigns the raw platform response straight into a `final T _data`
      // field with no null-check, so a `null`/`void` response cast to
      // `Map<String, dynamic>` throws a `TypeError` - not a
      // `FirebaseFunctionsException` - client-side, AFTER the Firestore
      // transaction has already committed. That threw a false "Network
      // error" on every successful delete (2026-09 physical-test finding);
      // `<dynamic>` accepts any response, including none, without a cast.
      await callable.call<dynamic>(<String, dynamic>{'productId': productId});
      return null;
    } on FirebaseFunctionsException catch (e) {
      return mapReviewCallableError(
        appCode: _appCodeOf(e),
        grpcCode: e.code,
        message: e.message,
      );
    } catch (_) {
      return 'Network error. Please check your connection and try again.';
    }
  }

  @override
  Future<String?> reportReview({
    required String reviewId,
    required ReviewReportReason reason,
    String? note,
  }) async {
    try {
      final callable = _functions.httpsCallable(
        'reportReview',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 30)),
      );
      await callable.call<Map<String, dynamic>>(<String, dynamic>{
        'reviewId': reviewId,
        'reason': reason.wireValue,
        'note': note,
      });
      return null;
    } on FirebaseFunctionsException catch (e) {
      return mapReviewCallableError(
        appCode: _appCodeOf(e),
        grpcCode: e.code,
        message: e.message,
      );
    } catch (_) {
      return 'Network error. Please check your connection and try again.';
    }
  }

  String? _appCodeOf(FirebaseFunctionsException e) {
    final details = e.details;
    if (details is Map) return details['appCode']?.toString();
    return null;
  }
}
