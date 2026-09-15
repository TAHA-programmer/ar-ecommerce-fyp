import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/widgets/review_star_row.dart';

void main() {
  Widget createWidget(double rating) {
    return MaterialApp(
      home: Scaffold(body: ReviewStarRow(rating: rating)),
    );
  }

  group('ReviewStarRow', () {
    testWidgets('always renders exactly 5 stars', (tester) async {
      await tester.pumpWidget(createWidget(3));
      final filled = tester.widgetList(find.byIcon(Icons.star_rounded)).length;
      final outlined = tester
          .widgetList(find.byIcon(Icons.star_outline_rounded))
          .length;
      expect(filled + outlined, 5);
    });

    testWidgets('rating 4 fills exactly 4 stars', (tester) async {
      await tester.pumpWidget(createWidget(4));
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
      expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(1));
    });

    testWidgets('rating 0 fills no stars', (tester) async {
      await tester.pumpWidget(createWidget(0));
      expect(find.byIcon(Icons.star_rounded), findsNothing);
      expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(5));
    });

    testWidgets('a fractional average rounds to the nearest whole star', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget(4.6));
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));

      await tester.pumpWidget(createWidget(4.4));
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(4));
    });

    testWidgets('an out-of-range rating is clamped, never crashes', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget(99));
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(5));

      await tester.pumpWidget(createWidget(-5));
      expect(find.byIcon(Icons.star_rounded), findsNothing);
    });
  });
}
