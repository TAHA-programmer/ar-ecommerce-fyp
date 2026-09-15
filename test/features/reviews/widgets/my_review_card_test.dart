import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/features/reviews/models/review_model.dart';
import 'package:twin_ar/features/reviews/models/review_status.dart';
import 'package:twin_ar/features/reviews/widgets/my_review_card.dart';

ReviewModel _review({
  String id = 'u1_p1',
  int rating = 4,
  String? title,
  String body = 'A perfectly good review body for this test case here.',
  ReviewStatus status = ReviewStatus.published,
}) {
  return ReviewModel(
    id: id,
    productId: 'p1',
    userId: 'u1',
    authorDisplayName: 'Ayesha K.',
    orderId: 'order-1',
    rating: rating,
    title: title,
    body: body,
    status: status,
    createdAt: DateTime(2026, 3, 15),
  );
}

const _summary = ProductSummaryModel(
  id: 'p1',
  title: 'Luna Accent Chair',
  imageAssetPath: 'assets/images/placeholder.png',
  currentPrice: 'Rs 12,000/-',
);

void main() {
  Widget createWidget({
    required ReviewModel review,
    ProductSummaryModel? productSummary,
    bool isDeleting = false,
    VoidCallback? onEdit,
    VoidCallback? onDelete,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: MyReviewCard(
          review: review,
          productSummary: productSummary,
          isDeleting: isDeleting,
          onEdit: onEdit ?? () {},
          onDelete: onDelete ?? () {},
        ),
      ),
    );
  }

  group('MyReviewCard', () {
    testWidgets('shows the resolved product title when a summary is given', (
      tester,
    ) async {
      await tester.pumpWidget(
        createWidget(review: _review(), productSummary: _summary),
      );
      expect(find.text('Luna Accent Chair'), findsOneWidget);
    });

    testWidgets('falls back to a generic label when no summary resolved', (
      tester,
    ) async {
      await tester.pumpWidget(createWidget(review: _review()));
      expect(find.text('Product'), findsOneWidget);
    });

    testWidgets('shows the review title and body', (tester) async {
      await tester.pumpWidget(
        createWidget(review: _review(title: 'Great chair')),
      );
      expect(find.text('Great chair'), findsOneWidget);
      expect(
        find.text('A perfectly good review body for this test case here.'),
        findsOneWidget,
      );
    });

    testWidgets('shows no status note for a published review', (tester) async {
      await tester.pumpWidget(createWidget(review: _review()));
      expect(find.textContaining('not currently visible'), findsNothing);
      expect(find.textContaining('not visible'), findsNothing);
    });

    testWidgets('shows a status note for a hidden review', (tester) async {
      await tester.pumpWidget(
        createWidget(review: _review(status: ReviewStatus.hidden)),
      );
      expect(find.textContaining('Hidden'), findsOneWidget);
    });

    testWidgets('shows a status note for a rejected review', (tester) async {
      await tester.pumpWidget(
        createWidget(review: _review(status: ReviewStatus.rejected)),
      );
      expect(find.textContaining('Rejected'), findsOneWidget);
    });

    testWidgets('tapping Edit invokes onEdit', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        createWidget(review: _review(), onEdit: () => tapped = true),
      );
      await tester.tap(find.text('Edit'));
      expect(tapped, true);
    });

    testWidgets('tapping Delete invokes onDelete', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        createWidget(review: _review(), onDelete: () => tapped = true),
      );
      await tester.tap(find.text('Delete'));
      expect(tapped, true);
    });

    testWidgets('Edit shows a pencil icon and Delete shows a bin icon, '
        'matching the app\'s design-system glyphs '
        '(address_card/review_write_entry)', (tester) async {
      await tester.pumpWidget(createWidget(review: _review()));

      final editIcon = tester.widget<Icon>(find.byIcon(Icons.edit_outlined));
      expect(editIcon.color, AppColors.primary);

      final deleteIcon = tester.widget<Icon>(find.byIcon(Icons.delete_outline));
      expect(deleteIcon.color, AppColors.error);
    });

    testWidgets('shows a spinner instead of Delete text while deleting, '
        'and disables both actions', (tester) async {
      var editTapped = false;
      var deleteTapped = false;
      await tester.pumpWidget(
        createWidget(
          review: _review(),
          isDeleting: true,
          onEdit: () => editTapped = true,
          onDelete: () => deleteTapped = true,
        ),
      );

      expect(find.text('Delete'), findsNothing);
      expect(find.byIcon(Icons.delete_outline), findsNothing);
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await tester.tap(find.text('Edit'), warnIfMissed: false);
      await tester.tap(
        find.byType(CircularProgressIndicator),
        warnIfMissed: false,
      );

      expect(editTapped, false);
      expect(deleteTapped, false);
    });
  });
}
