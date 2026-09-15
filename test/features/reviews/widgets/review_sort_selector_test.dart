import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/review_sort_option.dart';
import 'package:twin_ar/features/reviews/widgets/review_sort_selector.dart';

void main() {
  group('ReviewSortSelector', () {
    testWidgets('renders all three sort options', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewSortSelector(
              selected: ReviewSortOption.newest,
              onChanged: (_) {},
            ),
          ),
        ),
      );

      expect(find.text('Newest'), findsOneWidget);
      expect(find.text('Highest Rated'), findsOneWidget);
      expect(find.text('Lowest Rated'), findsOneWidget);
    });

    testWidgets('tapping an option invokes onChanged with that option', (
      tester,
    ) async {
      ReviewSortOption? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewSortSelector(
              selected: ReviewSortOption.newest,
              onChanged: (option) => tapped = option,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Highest Rated'));
      await tester.pump();

      expect(tapped, ReviewSortOption.highestRating);
    });

    testWidgets('tapping the already-selected option still invokes '
        'onChanged (the ViewModel itself is the no-op guard)', (tester) async {
      var tapCount = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ReviewSortSelector(
              selected: ReviewSortOption.newest,
              onChanged: (_) => tapCount++,
            ),
          ),
        ),
      );

      await tester.tap(find.text('Newest'));
      await tester.pump();

      expect(tapCount, 1);
    });
  });
}
