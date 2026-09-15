import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/product_rating_stats.dart';

void main() {
  group('ProductRatingStats.zero', () {
    test('has no reviews and a zero average - the honest empty state', () {
      expect(ProductRatingStats.zero.hasReviews, false);
      expect(ProductRatingStats.zero.averageRating, 0.0);
      expect(ProductRatingStats.zero.ratingCount, 0);
    });

    test('fractionForStars is 0.0 for every star with no reviews (no '
        'divide-by-zero)', () {
      for (var stars = 1; stars <= 5; stars++) {
        expect(ProductRatingStats.zero.fractionForStars(stars), 0.0);
      }
    });
  });

  group('ProductRatingStats.countForStars / fractionForStars', () {
    const stats = ProductRatingStats(
      ratingSum: 43,
      ratingCount: 10,
      averageRating: 4.3,
      rating1Count: 0,
      rating2Count: 1,
      rating3Count: 1,
      rating4Count: 3,
      rating5Count: 5,
    );

    test('countForStars returns the exact bucket', () {
      expect(stats.countForStars(1), 0);
      expect(stats.countForStars(5), 5);
    });

    test('countForStars returns 0 for an out-of-range value, never throws', () {
      expect(stats.countForStars(0), 0);
      expect(stats.countForStars(6), 0);
    });

    test('fractionForStars divides by the total count', () {
      expect(stats.fractionForStars(5), 5 / 10);
      expect(stats.fractionForStars(4), 3 / 10);
    });

    test('hasReviews is true once ratingCount > 0', () {
      expect(stats.hasReviews, true);
    });
  });
}
