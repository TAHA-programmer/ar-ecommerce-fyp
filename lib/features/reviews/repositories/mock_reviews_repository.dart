import '../models/product_rating_stats.dart';
import '../models/review_model.dart';
import '../models/review_report_model.dart';
import '../models/review_report_reason.dart';
import '../models/review_sort_option.dart';
import '../models/review_status.dart';
import '../models/review_validation.dart';
import '../models/reviews_page.dart';
import '../utils/review_author_display_name.dart';
import 'reviews_repository.dart';

/// In-memory [ReviewsRepository] - both a test double AND, deliberately, a
/// faithful reference implementation of the v1 business rules the real
/// `submitReview`/`deleteReview`/`reportReview` Cloud Functions (Stage 2/3)
/// must replicate server-side: one review per user per product via the
/// deterministic doc id, the 30-day edit window measured from the ORIGINAL
/// `createdAt`, transactional rating-aggregate maintenance that reverses an
/// edited/deleted review's OLD contribution before applying the new one,
/// and unique-reporter counting with a report-count flag threshold. Getting
/// this right here, unit-tested, before any server code exists, is the
/// point of Stage 1.
///
/// Deliberately does NOT model real Firestore `orders` - eligibility is
/// whatever [markEligible]/[markIneligible] configure per user/product, so
/// this stays a pure reviews-business-rules double; the real
/// order-scanning eligibility check is `FirestoreReviewsRepository`'s job
/// (Stage 5), reading the actual `orders` collection.
class MockReviewsRepository implements ReviewsRepository {
  /// The signed-in customer's uid this instance acts as. Change it directly
  /// between calls in a test to simulate a different customer.
  String currentUserId;

  /// Injectable clock - tests set this to move "now" past the 30-day edit
  /// window without a real `Duration`-based sleep.
  DateTime Function() now;

  final Map<String, ReviewModel> _reviewsById = {};
  final Map<String, ReviewReportModel> _reportsById = {};

  /// `userId -> eligible productIds` (see [markEligible]). Each entry also
  /// supplies the `orderId` that made them eligible, since a genuine review
  /// needs one for its audit trail.
  final Map<String, Map<String, String>> _eligibility = {};

  /// `userId -> raw profile displayName` (see [setDisplayName]) - mirrors
  /// what the real `submitReview` callable reads from `users/{uid}` via the
  /// Admin SDK. An unconfigured user masks to
  /// [kFallbackReviewerDisplayName], exactly like a real profile with a
  /// blank/missing `displayName`.
  final Map<String, String> displayNamesByUserId;

  MockReviewsRepository({
    this.currentUserId = 'mock-uid',
    DateTime Function()? now,
    Map<String, String>? displayNamesByUserId,
  }) : now = now ?? DateTime.now,
       displayNamesByUserId = displayNamesByUserId ?? {};

  /// Test setup: [userId]'s raw (unmasked) profile display name - the SAME
  /// masking [submitReview] applies mirrors
  /// `functions/src/lib/reviews/authorDisplayName.ts`'s server-side logic.
  void setDisplayName(String userId, String displayName) {
    displayNamesByUserId[userId] = displayName;
  }

  /// Test setup: [userId] may now review [productId], attributing the
  /// review to [orderId] (defaults to a synthetic id) when they do.
  void markEligible(
    String userId,
    String productId, {
    String orderId = 'mock-order',
  }) {
    (_eligibility[userId] ??= {})[productId] = orderId;
  }

  void markIneligible(String userId, String productId) {
    _eligibility[userId]?.remove(productId);
  }

  @override
  Future<bool> isEligibleToReview(String productId) async {
    return _eligibility[currentUserId]?.containsKey(productId) ?? false;
  }

  @override
  Future<List<ReviewModel>> myReviews() async {
    final mine =
        _reviewsById.values.where((r) => r.userId == currentUserId).toList()
          ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return mine;
  }

  @override
  Future<ReviewModel?> myReviewFor(String productId) async {
    final id = ReviewModel.docIdFor(
      userId: currentUserId,
      productId: productId,
    );
    return _reviewsById[id];
  }

  @override
  Future<String?> submitReview({
    required String productId,
    required int rating,
    String? title,
    required String body,
  }) async {
    if (!ReviewValidation.isRatingValid(rating)) {
      return 'Please select a rating between 1 and 5 stars.';
    }
    if (!ReviewValidation.isTitleValid(title)) {
      return 'Review title is too long.';
    }
    if (!ReviewValidation.isBodyValid(body)) {
      return 'Your review must be between '
          '${ReviewValidation.minBodyLength} and '
          '${ReviewValidation.maxBodyLength} characters.';
    }

    final orderId = _eligibility[currentUserId]?[productId];
    if (orderId == null) {
      return 'You can only review products from a delivered order.';
    }

    final id = ReviewModel.docIdFor(
      userId: currentUserId,
      productId: productId,
    );
    final existing = _reviewsById[id];
    final nowValue = now();
    // Resolved fresh on every submit (create AND edit) - mirrors the real
    // callable re-reading `users/{uid}` each time, so a since-changed
    // profile name is reflected on a later edit.
    final authorDisplayName = maskReviewerDisplayName(
      displayNamesByUserId[currentUserId],
    );

    if (existing != null) {
      if (!existing.isEditableAt(nowValue)) {
        return 'This review can no longer be edited '
            '(the ${ReviewValidation.editWindowDays}-day edit window has '
            'passed).';
      }
      _reverseAggregate(existing);
      final updated = ReviewModel(
        id: id,
        productId: productId,
        userId: currentUserId,
        authorDisplayName: authorDisplayName,
        orderId: existing.orderId,
        rating: rating,
        title: title,
        body: body,
        status: ReviewStatus.published,
        reportCount: existing.reportCount,
        flaggedForReview: existing.flaggedForReview,
        createdAt: existing.createdAt,
        editedAt: nowValue,
      );
      _reviewsById[id] = updated;
      _applyAggregate(updated);
      return null;
    }

    final created = ReviewModel(
      id: id,
      productId: productId,
      userId: currentUserId,
      authorDisplayName: authorDisplayName,
      orderId: orderId,
      rating: rating,
      title: title,
      body: body,
      createdAt: nowValue,
    );
    _reviewsById[id] = created;
    _applyAggregate(created);
    return null;
  }

  @override
  Future<String?> deleteReview(String productId) async {
    final id = ReviewModel.docIdFor(
      userId: currentUserId,
      productId: productId,
    );
    final existing = _reviewsById.remove(id);
    if (existing == null) return null;
    _reverseAggregate(existing);
    return null;
  }

  @override
  Future<String?> reportReview({
    required String reviewId,
    required ReviewReportReason reason,
    String? note,
  }) async {
    final review = _reviewsById[reviewId];
    if (review == null) return 'This review no longer exists.';

    final reportId = ReviewReportModel.docIdFor(
      reporterId: currentUserId,
      reviewId: reviewId,
    );
    final alreadyReported = _reportsById.containsKey(reportId);
    _reportsById[reportId] = ReviewReportModel(
      id: reportId,
      reviewId: reviewId,
      reporterId: currentUserId,
      reason: reason,
      note: note,
      createdAt: now(),
    );

    if (!alreadyReported) {
      final newCount = review.reportCount + 1;
      _reviewsById[reviewId] = review.copyWith(
        reportCount: newCount,
        flaggedForReview:
            newCount >= ReviewValidation.reportFlagThreshold ||
            review.flaggedForReview,
      );
    }
    return null;
  }

  @override
  Future<ReviewsPage> fetchReviews({
    required String productId,
    ReviewSortOption sort = ReviewSortOption.newest,
    String? cursor,
    int pageSize = 10,
  }) async {
    final all =
        _reviewsById.values
            .where(
              (r) =>
                  r.productId == productId &&
                  r.status == ReviewStatus.published,
            )
            .toList()
          ..sort(_comparatorFor(sort));

    final start = cursor == null ? 0 : int.tryParse(cursor) ?? 0;
    final end = (start + pageSize).clamp(0, all.length);
    final page = start >= all.length
        ? const <ReviewModel>[]
        : all.sublist(start, end);
    final next = end < all.length ? '$end' : null;
    return ReviewsPage(reviews: page, nextCursor: next);
  }

  int Function(ReviewModel, ReviewModel) _comparatorFor(ReviewSortOption sort) {
    switch (sort) {
      case ReviewSortOption.newest:
        return (a, b) => b.createdAt.compareTo(a.createdAt);
      case ReviewSortOption.highestRating:
        return (a, b) => b.rating.compareTo(a.rating);
      case ReviewSortOption.lowestRating:
        return (a, b) => a.rating.compareTo(b.rating);
    }
  }

  @override
  Future<ProductRatingStats> ratingStatsFor(String productId) async {
    return _statsByProduct[productId] ?? ProductRatingStats.zero;
  }

  final Map<String, ProductRatingStats> _statsByProduct = {};

  void _applyAggregate(ReviewModel review) {
    if (!review.status.countsTowardAggregate) return;
    final current =
        _statsByProduct[review.productId] ?? ProductRatingStats.zero;
    _statsByProduct[review.productId] = _withDelta(current, review.rating, 1);
  }

  void _reverseAggregate(ReviewModel review) {
    if (!review.status.countsTowardAggregate) return;
    final current =
        _statsByProduct[review.productId] ?? ProductRatingStats.zero;
    _statsByProduct[review.productId] = _withDelta(current, review.rating, -1);
  }

  ProductRatingStats _withDelta(
    ProductRatingStats stats,
    int rating,
    int delta,
  ) {
    final newCount = stats.ratingCount + delta;
    final newSum = stats.ratingSum + (rating * delta);
    int r1 = stats.rating1Count, r2 = stats.rating2Count;
    int r3 = stats.rating3Count, r4 = stats.rating4Count;
    int r5 = stats.rating5Count;
    switch (rating) {
      case 1:
        r1 += delta;
        break;
      case 2:
        r2 += delta;
        break;
      case 3:
        r3 += delta;
        break;
      case 4:
        r4 += delta;
        break;
      case 5:
        r5 += delta;
        break;
    }
    return ProductRatingStats(
      ratingSum: newSum,
      ratingCount: newCount,
      averageRating: newCount > 0 ? newSum / newCount : 0.0,
      rating1Count: r1,
      rating2Count: r2,
      rating3Count: r3,
      rating4Count: r4,
      rating5Count: r5,
    );
  }
}
