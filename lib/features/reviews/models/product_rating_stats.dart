/// The rating-aggregate fields on a `productStats/{productId}` document
/// (Ratings/Reviews v1 §2) - a handful of NEW flat fields alongside the
/// EXISTING `unitsSold`/`favoriteCount` etc. from Dynamic Home Content
/// Stage 2, never a replacement of that document.
///
/// Maintained EXCLUSIVELY, transactionally, by the `submitReview`/
/// `deleteReview`/`moderateReview` Cloud Functions (Stage 2/3) - only
/// [ReviewStatus.published] reviews ever contribute (v1 §0 decision 15).
/// A client only ever reads this; `firestore.rules`' existing
/// `productStats` rule (`read: isSignedIn(); write: false`) is unchanged.
class ProductRatingStats {
  final int ratingSum;
  final int ratingCount;
  final double averageRating;
  final int rating1Count;
  final int rating2Count;
  final int rating3Count;
  final int rating4Count;
  final int rating5Count;

  const ProductRatingStats({
    required this.ratingSum,
    required this.ratingCount,
    required this.averageRating,
    required this.rating1Count,
    required this.rating2Count,
    required this.rating3Count,
    required this.rating4Count,
    required this.rating5Count,
  });

  /// A product with no published reviews yet - the honest "No reviews yet" /
  /// "(0)" empty state (v1 §0 decision 16), never a fabricated placeholder
  /// number.
  static const ProductRatingStats zero = ProductRatingStats(
    ratingSum: 0,
    ratingCount: 0,
    averageRating: 0.0,
    rating1Count: 0,
    rating2Count: 0,
    rating3Count: 0,
    rating4Count: 0,
    rating5Count: 0,
  );

  bool get hasReviews => ratingCount > 0;

  /// The count for a given star value (1-5). Out-of-range returns `0`
  /// rather than throwing - a defensive read, never a crash on bad data.
  int countForStars(int stars) {
    switch (stars) {
      case 1:
        return rating1Count;
      case 2:
        return rating2Count;
      case 3:
        return rating3Count;
      case 4:
        return rating4Count;
      case 5:
        return rating5Count;
      default:
        return 0;
    }
  }

  /// The fraction (0.0-1.0) of published reviews that gave [stars] - the
  /// distribution-bar fill ratio. `0.0` when there are no reviews yet
  /// (never a divide-by-zero).
  double fractionForStars(int stars) {
    if (ratingCount <= 0) return 0.0;
    return countForStars(stars) / ratingCount;
  }
}
