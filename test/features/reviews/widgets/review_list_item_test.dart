import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/review_model.dart';
import 'package:twin_ar/features/reviews/widgets/review_list_item.dart';

void main() {
  Widget createWidget(ReviewModel review, {VoidCallback? onReport}) {
    return MaterialApp(
      home: Scaffold(
        body: ReviewListItem(review: review, onReport: onReport),
      ),
    );
  }

  group('ReviewListItem', () {
    testWidgets('shows the masked author name, body, and formatted date', (
      tester,
    ) async {
      final review = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Ayesha K.',
        orderId: 'order-1',
        rating: 5,
        body: 'Absolutely love this chair, very comfortable.',
        createdAt: DateTime(2026, 3, 15),
      );

      await tester.pumpWidget(createWidget(review));

      expect(find.text('Ayesha K.'), findsOneWidget);
      expect(
        find.text('Absolutely love this chair, very comfortable.'),
        findsOneWidget,
      );
      expect(find.text('Mar 15, 2026'), findsOneWidget);
      // Never renders the raw userId as if it were the author's identity.
      expect(find.text('u1'), findsNothing);
    });

    testWidgets('shows the title when present', (tester) async {
      final review = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Ayesha K.',
        orderId: 'order-1',
        rating: 4,
        title: 'Great value',
        body: 'Solid build quality for the price.',
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(createWidget(review));

      expect(find.text('Great value'), findsOneWidget);
    });

    testWidgets('omits the title block when there is none', (tester) async {
      final review = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Ayesha K.',
        orderId: 'order-1',
        rating: 3,
        body: 'Its fine.',
        createdAt: DateTime(2026, 1, 1),
      );

      await tester.pumpWidget(createWidget(review));
      expect(find.text('Its fine.'), findsOneWidget);
    });

    testWidgets('shows an "Edited" note only once the review has been '
        'edited', (tester) async {
      final unedited = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Ayesha K.',
        orderId: 'order-1',
        rating: 5,
        body: 'Great.',
        createdAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(createWidget(unedited));
      expect(find.text('Edited'), findsNothing);

      final edited = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Ayesha K.',
        orderId: 'order-1',
        rating: 5,
        body: 'Great, updated my thoughts after a month of use.',
        createdAt: DateTime(2026, 1, 1),
        editedAt: DateTime(2026, 1, 10),
      );
      await tester.pumpWidget(createWidget(edited));
      expect(find.text('Edited'), findsOneWidget);
    });

    testWidgets('renders exactly the rating\'s number of filled stars', (
      tester,
    ) async {
      final review = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Ayesha K.',
        orderId: 'order-1',
        rating: 2,
        body: 'Not great, expected better quality.',
        createdAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(createWidget(review));
      expect(find.byIcon(Icons.star_rounded), findsNWidgets(2));
      expect(find.byIcon(Icons.star_outline_rounded), findsNWidgets(3));
    });

    testWidgets('shows the fallback name for a review with no configured '
        'display name', (tester) async {
      final review = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Verified Buyer',
        orderId: 'order-1',
        rating: 4,
        body: 'A perfectly ordinary review with no special profile name.',
        createdAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(createWidget(review));
      expect(find.text('Verified Buyer'), findsOneWidget);
    });

    testWidgets('omits the Report action when onReport is null', (
      tester,
    ) async {
      final review = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Ayesha K.',
        orderId: 'order-1',
        rating: 5,
        body: 'A review with no report action available at all here.',
        createdAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(createWidget(review));
      expect(find.text('Report'), findsNothing);
    });

    testWidgets('shows a Report action and invokes onReport when tapped', (
      tester,
    ) async {
      var reported = false;
      final review = ReviewModel(
        id: 'u1_p1',
        productId: 'p1',
        userId: 'u1',
        authorDisplayName: 'Ayesha K.',
        orderId: 'order-1',
        rating: 5,
        body: 'A review that can be reported by another customer here.',
        createdAt: DateTime(2026, 1, 1),
      );
      await tester.pumpWidget(
        createWidget(review, onReport: () => reported = true),
      );

      expect(find.text('Report'), findsOneWidget);
      await tester.tap(find.text('Report'));
      await tester.pump();
      expect(reported, true);
    });
  });
}
