import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/product_rating_stats.dart';
import 'package:twin_ar/features/reviews/widgets/review_rating_summary.dart';

void main() {
  Widget createWidget(ProductRatingStats stats) {
    return MaterialApp(
      home: Scaffold(body: ReviewRatingSummary(stats: stats)),
    );
  }

  group('ReviewRatingSummary', () {
    testWidgets('shows the average rating and singular "1 review"', (
      tester,
    ) async {
      const stats = ProductRatingStats(
        ratingSum: 4,
        ratingCount: 1,
        averageRating: 4.0,
        rating1Count: 0,
        rating2Count: 0,
        rating3Count: 0,
        rating4Count: 1,
        rating5Count: 0,
      );
      await tester.pumpWidget(createWidget(stats));

      expect(find.text('4.0'), findsOneWidget);
      expect(find.text('1 review'), findsOneWidget);
    });

    testWidgets('shows plural "N reviews" and every distribution count', (
      tester,
    ) async {
      // Counts deliberately avoid the 1-5 range so they can never be
      // confused with a row's own "N★" star-index label (also a bare
      // digit Text widget) when asserting on `find.text`.
      const stats = ProductRatingStats(
        ratingSum: 138,
        ratingCount: 27,
        averageRating: 4.0,
        rating1Count: 0,
        rating2Count: 6,
        rating3Count: 0,
        rating4Count: 9,
        rating5Count: 12,
      );
      await tester.pumpWidget(createWidget(stats));

      expect(find.text('4.0'), findsOneWidget);
      expect(find.text('27 reviews'), findsOneWidget);
      // Distribution row counts: 5★=12, 4★=9, 3★=0, 2★=6, 1★=0.
      expect(find.text('12'), findsOneWidget);
      expect(find.text('9'), findsOneWidget);
      expect(find.text('6'), findsOneWidget);
      expect(find.text('0'), findsNWidgets(2)); // 3★ and 1★ counts
    });

    testWidgets('the zero aggregate renders honestly - 0.0, no reviews, '
        'empty bars', (tester) async {
      await tester.pumpWidget(createWidget(ProductRatingStats.zero));

      expect(find.text('0.0'), findsOneWidget);
      expect(find.text('0 reviews'), findsOneWidget);
    });
  });
}
