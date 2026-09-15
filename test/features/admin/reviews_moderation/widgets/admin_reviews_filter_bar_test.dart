import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/admin/reviews_moderation/models/admin_review_filter.dart';
import 'package:twin_ar/features/admin/reviews_moderation/widgets/admin_reviews_filter_bar.dart';

void main() {
  Widget createWidget({
    AdminReviewFilter selected = AdminReviewFilter.all,
    int flaggedCount = 0,
    ValueChanged<AdminReviewFilter>? onChanged,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AdminReviewsFilterBar(
          selected: selected,
          flaggedCount: flaggedCount,
          onChanged: onChanged ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('renders every filter label', (tester) async {
    await tester.pumpWidget(createWidget());
    for (final filter in AdminReviewFilter.values) {
      expect(find.text(filter.label), findsOneWidget);
    }
  });

  testWidgets('shows a badge on Flagged only when flaggedCount > 0', (
    tester,
  ) async {
    await tester.pumpWidget(createWidget(flaggedCount: 0));
    expect(find.text('0'), findsNothing);

    await tester.pumpWidget(createWidget(flaggedCount: 5));
    expect(find.text('5'), findsOneWidget);
  });

  testWidgets('tapping a chip reports the tapped filter', (tester) async {
    AdminReviewFilter? tapped;
    await tester.pumpWidget(createWidget(onChanged: (f) => tapped = f));

    await tester.tap(find.text('Hidden'));
    await tester.pump();

    expect(tapped, AdminReviewFilter.hidden);
  });
}
