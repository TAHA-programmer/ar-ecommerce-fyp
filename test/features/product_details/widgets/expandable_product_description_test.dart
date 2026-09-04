import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/product_details/widgets/expandable_product_description.dart';

void main() {
  Widget createWidget(String text) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ExpandableProductDescription(description: text),
        ),
      ),
    );
  }

  group('ExpandableProductDescription Tests', () {
    testWidgets('short text does not show Read More', (
      WidgetTester tester,
    ) async {
      const shortText = 'This is a short description.';

      await tester.pumpWidget(createWidget(shortText));
      await tester.pumpAndSettle();

      expect(find.text(shortText), findsOneWidget);
      expect(find.text('Read More'), findsNothing);
      expect(find.text('Read Less'), findsNothing);
    });

    testWidgets('long text shows Read More and expands', (
      WidgetTester tester,
    ) async {
      // Create a very long string that will definitely exceed 3 lines
      final longText = 'Line 1\n' * 10;

      await tester.pumpWidget(createWidget(longText));
      await tester.pumpAndSettle();

      // Should show 'Read More' initially
      expect(find.text('Read More'), findsOneWidget);
      expect(find.text('Read Less'), findsNothing);

      // Tap 'Read More'
      await tester.tap(find.text('Read More'));
      await tester.pumpAndSettle();

      // Now it should be expanded
      expect(find.text('Read Less'), findsOneWidget);
      expect(find.text('Read More'), findsNothing);

      // Tap 'Read Less'
      await tester.tap(find.text('Read Less'));
      await tester.pumpAndSettle();

      // Should go back to collapsed
      expect(find.text('Read More'), findsOneWidget);
      expect(find.text('Read Less'), findsNothing);
    });
  });
}
