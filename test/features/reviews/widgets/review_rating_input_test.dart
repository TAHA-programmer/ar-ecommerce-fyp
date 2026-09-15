import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/widgets/review_rating_input.dart';

void main() {
  group('ReviewRatingInput', () {
    testWidgets('renders 5 stars, all outlined when rating is 0', (
      tester,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReviewRatingInput(rating: 0, onChanged: (_) {})),
        ),
      );

      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
    });

    testWidgets('fills exactly the given number of stars', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ReviewRatingInput(rating: 3, onChanged: (_) {})),
        ),
      );

      expect(find.byIcon(Icons.star_rounded), findsNWidgets(3));
      expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(2));
    });

    testWidgets('tapping the Nth star invokes onChanged with N', (
      tester,
    ) async {
      int? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewRatingInput(
              rating: 0,
              onChanged: (value) => tapped = value,
            ),
          ),
        ),
      );

      final buttons = find.byType(IconButton);
      expect(buttons, findsNWidgets(5));
      await tester.tap(buttons.at(3)); // 4th star (1-indexed value 4)
      await tester.pump();

      expect(tapped, 4);
    });
  });
}
