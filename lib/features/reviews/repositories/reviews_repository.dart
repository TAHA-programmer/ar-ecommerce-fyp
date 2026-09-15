import '../models/product_rating_stats.dart';
import '../models/review_model.dart';
import '../models/review_report_reason.dart';
import '../models/review_sort_option.dart';
import '../models/reviews_page.dart';

/// Ratings/Reviews v1 data contract (`24_RATINGS_REVIEWS_FEEDBACK_PLAN.md`).
///
/// Every MUTATING method here is a thin client-side wrapper around a
/// server-side callable Cloud Function (`submitReview`/`deleteReview`/
/// `reportReview` - Stage 2/3) - `firestore.rules` denies every direct
/// client write to `reviews`/`reviewReports` (v1 §0 decision 14), so a real
/// implementation of this interface NEVER performs a Firestore `set`/
/// `update`/`delete` itself; it only ever calls a callable and reports back
/// its result. Every READ method reflects a real Firestore query the
/// existing rules already allow a signed-in customer (their own review,
/// their own eligibility, and the public published-review list/aggregate).
///
/// Mirrors this codebase's established "clean error message, not a thrown
/// exception" convention for customer-facing actions (see
/// `CustomerShoppingState.toggleFavorite`/`addToCart`,
/// `CartViewModel.updateQuantity`): every mutating method returns `null` on
/// success or an `AppToast`-ready message on failure.
abstract class ReviewsRepository {
  /// A page of PUBLISHED reviews for [productId], ordered by [sort].
  /// [cursor] is a previous [ReviewsPage.nextCursor] to continue from
  /// (`null` for the first page). Never throws - a read failure (offline,
  /// permission-denied, the collection not deployed yet) resolves to
  /// [ReviewsPage.empty], matching `ProductStatsRepository`'s established
  /// resilience contract, so a broken reviews backend never crashes or
  /// error-bars the rest of Product Details.
  Future<ReviewsPage> fetchReviews({
    required String productId,
    ReviewSortOption sort = ReviewSortOption.newest,
    String? cursor,
    int pageSize = 10,
  });

  /// The rating aggregate for [productId] - the summary number + 1-5 star
  /// distribution. Returns [ProductRatingStats.zero] (never throws) when
  /// the product genuinely has no reviews yet OR the read failed - both
  /// render the same honest "No reviews yet" empty state, never a
  /// fabricated number (v1 §0 decision 16).
  Future<ProductRatingStats> ratingStatsFor(String productId);

  /// The signed-in customer's own review for [productId], or `null` if they
  /// haven't reviewed it (or aren't signed in, or the read failed - all
  /// three fail closed to "no existing review", never an exception).
  Future<ReviewModel?> myReviewFor(String productId);

  /// Every review the signed-in customer has ever written, across ALL
  /// products, newest first - including a `hidden`/`rejected` one (the
  /// author can always see their own review regardless of moderation
  /// status, matching `firestore.rules`). Powers the Profile "My Reviews"
  /// screen (Stage 7). Never throws - `[]` when signed out or on any read
  /// failure, matching every other read method's fail-closed contract.
  Future<List<ReviewModel>> myReviews();

  /// `true` only when the signed-in customer has a `delivered` order
  /// containing [productId] (v1 §0 decision 1) AND that order was placed by
  /// them - a DISPLAY-ONLY convenience read (drives whether "Write a
  /// Review" appears at all); the real, authoritative gate is re-checked
  /// server-side inside `submitReview` regardless of what this returns.
  /// Fails closed to `false` on any read error - never shows a write
  /// affordance it can't back up.
  Future<bool> isEligibleToReview(String productId);

  /// Creates a NEW review, or edits the caller's existing one for
  /// [productId] (the deterministic doc id makes this the same operation -
  /// see `ReviewModel.docIdFor`). An edit past
  /// `ReviewValidation.editWindowDays` since the ORIGINAL submission is
  /// refused server-side with a clean message. Returns `null` on success.
  Future<String?> submitReview({
    required String productId,
    required int rating,
    String? title,
    required String body,
  });

  /// Deletes the caller's own review for [productId]. No time limit (v1 §0
  /// decision 7). Returns `null` on success.
  Future<String?> deleteReview(String productId);

  /// Reports someone else's review. A repeat report from the same customer
  /// for the same [reviewId] is a harmless no-op, never a duplicate count
  /// (v1 §0 decision 10 - one report per user per review). Returns `null`
  /// on success.
  Future<String?> reportReview({
    required String reviewId,
    required ReviewReportReason reason,
    String? note,
  });
}
