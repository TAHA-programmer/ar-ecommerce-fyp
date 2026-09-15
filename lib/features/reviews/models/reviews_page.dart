import 'review_model.dart';

/// One page of a product's PUBLISHED review list (Ratings/Reviews v1 §0
/// decision 9 - 10 per page, newest-first by default), plus the cursor for
/// "Load more reviews" (`ReviewsRepository.fetchReviews`'s `cursor` param).
class ReviewsPage {
  final List<ReviewModel> reviews;

  /// Opaque cursor to pass back as `fetchReviews`'s `cursor` for the next
  /// page. `null` means there is no further page.
  final String? nextCursor;

  const ReviewsPage({required this.reviews, this.nextCursor});

  static const ReviewsPage empty = ReviewsPage(reviews: []);

  bool get hasMore => nextCursor != null;
}
