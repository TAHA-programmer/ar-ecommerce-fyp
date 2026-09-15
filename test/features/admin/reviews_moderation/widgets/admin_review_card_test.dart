import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/features/admin/reviews_moderation/widgets/admin_review_card.dart';
import 'package:twin_ar/features/reviews/models/review_model.dart';
import 'package:twin_ar/features/reviews/models/review_moderation_action.dart';
import 'package:twin_ar/features/reviews/models/review_report_model.dart';
import 'package:twin_ar/features/reviews/models/review_report_reason.dart';
import 'package:twin_ar/features/reviews/models/review_status.dart';

ReviewModel _review({
  ReviewStatus status = ReviewStatus.published,
  bool flaggedForReview = false,
  int reportCount = 0,
  String? moderationReason,
  DateTime? moderatedAt,
}) {
  return ReviewModel(
    id: 'u1_p1',
    productId: 'p1',
    userId: 'u1',
    authorDisplayName: 'Ayesha K.',
    orderId: 'order-1',
    rating: 4,
    body: 'A review body long enough to pass validation checks.',
    status: status,
    reportCount: reportCount,
    flaggedForReview: flaggedForReview,
    createdAt: DateTime(2026, 1, 1),
    moderationReason: moderationReason,
    moderatedAt: moderatedAt,
  );
}

void main() {
  Widget createWidget({
    ReviewModel? review,
    ProductSummaryModel? productSummary,
    bool isModerating = false,
    List<ReviewReportModel>? reports,
    bool isLoadingReports = false,
    VoidCallback? onLoadReports,
    ValueChanged<ReviewModerationAction>? onModerate,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: AdminReviewCard(
          review: review ?? _review(),
          productSummary: productSummary,
          isModerating: isModerating,
          reports: reports,
          isLoadingReports: isLoadingReports,
          onLoadReports: onLoadReports ?? () {},
          onModerate: onModerate ?? (_) {},
        ),
      ),
    );
  }

  testWidgets('shows the resolved product title, or falls back to the raw '
      'productId when unresolved', (tester) async {
    await tester.pumpWidget(
      createWidget(
        productSummary: ProductSummaryModel(
          id: 'p1',
          title: 'Luna Accent Chair',
          imageAssetPath: 'assets/images/placeholder.png',
          currentPrice: 'Rs 1,000/-',
        ),
      ),
    );
    expect(find.text('Luna Accent Chair'), findsOneWidget);

    await tester.pumpWidget(createWidget(productSummary: null));
    expect(find.text('p1'), findsOneWidget);
  });

  testWidgets('shows the correct status badge for each status', (tester) async {
    await tester.pumpWidget(
      createWidget(review: _review(status: ReviewStatus.published)),
    );
    expect(find.text('Published'), findsOneWidget);

    await tester.pumpWidget(
      createWidget(review: _review(status: ReviewStatus.hidden)),
    );
    expect(find.text('Hidden'), findsOneWidget);

    await tester.pumpWidget(
      createWidget(review: _review(status: ReviewStatus.rejected)),
    );
    expect(find.text('Rejected'), findsOneWidget);
  });

  testWidgets('shows a flagged badge with the report count only when '
      'flagged', (tester) async {
    await tester.pumpWidget(
      createWidget(review: _review(flaggedForReview: false)),
    );
    expect(find.textContaining('Flagged'), findsNothing);

    await tester.pumpWidget(
      createWidget(review: _review(flaggedForReview: true, reportCount: 4)),
    );
    expect(find.textContaining('Flagged - 4 reports'), findsOneWidget);
  });

  testWidgets('shows the moderation note when the review has been '
      'moderated', (tester) async {
    await tester.pumpWidget(
      createWidget(
        review: _review(
          status: ReviewStatus.hidden,
          moderationReason: 'Contains spam links.',
          moderatedAt: DateTime(2026, 2, 1),
        ),
      ),
    );
    expect(find.textContaining('Contains spam links.'), findsOneWidget);
  });

  testWidgets('omits the moderation note for a never-moderated review', (
    tester,
  ) async {
    await tester.pumpWidget(createWidget());
    expect(find.textContaining('Moderation note'), findsNothing);
  });

  testWidgets('"View reports" only appears when reportCount > 0, and '
      'expanding it loads then shows the reports', (tester) async {
    var loadCalled = false;
    await tester.pumpWidget(createWidget(review: _review(reportCount: 0)));
    expect(find.textContaining('View reports'), findsNothing);

    await tester.pumpWidget(
      createWidget(
        review: _review(reportCount: 2),
        onLoadReports: () => loadCalled = true,
        reports: [
          ReviewReportModel(
            id: 'a_u1_p1',
            reviewId: 'u1_p1',
            reporterId: 'a',
            reason: ReviewReportReason.spam,
            createdAt: DateTime(2026, 1, 2),
          ),
        ],
      ),
    );
    expect(find.text('View reports (2)'), findsOneWidget);

    await tester.tap(find.text('View reports (2)'));
    await tester.pump();

    expect(loadCalled, true);
    expect(find.textContaining('Spam'), findsOneWidget);
    expect(find.text('Hide reports'), findsOneWidget);
  });

  testWidgets('shows a loading spinner while reports are loading', (
    tester,
  ) async {
    await tester.pumpWidget(
      createWidget(review: _review(reportCount: 1), isLoadingReports: true),
    );
    await tester.tap(find.text('View reports (1)'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsWidgets);
  });

  testWidgets('published shows Hide + Reject, never Restore', (tester) async {
    await tester.pumpWidget(
      createWidget(review: _review(status: ReviewStatus.published)),
    );
    expect(find.text('Hide Review'), findsOneWidget);
    expect(find.text('Reject Review'), findsOneWidget);
    expect(find.text('Restore Review'), findsNothing);
  });

  testWidgets('hidden shows Restore + Reject, never Hide', (tester) async {
    await tester.pumpWidget(
      createWidget(review: _review(status: ReviewStatus.hidden)),
    );
    expect(find.text('Restore Review'), findsOneWidget);
    expect(find.text('Reject Review'), findsOneWidget);
    expect(find.text('Hide Review'), findsNothing);
  });

  testWidgets('rejected shows Restore + Hide, never Reject', (tester) async {
    await tester.pumpWidget(
      createWidget(review: _review(status: ReviewStatus.rejected)),
    );
    expect(find.text('Restore Review'), findsOneWidget);
    expect(find.text('Hide Review'), findsOneWidget);
    expect(find.text('Reject Review'), findsNothing);
  });

  testWidgets('tapping an action button reports the tapped action', (
    tester,
  ) async {
    ReviewModerationAction? tapped;
    await tester.pumpWidget(
      createWidget(
        review: _review(status: ReviewStatus.published),
        onModerate: (a) => tapped = a,
      ),
    );
    await tester.tap(find.text('Hide Review'));
    await tester.pump();
    expect(tapped, ReviewModerationAction.hide);
  });

  testWidgets('while moderating, action buttons are disabled and a spinner '
      'shows', (tester) async {
    await tester.pumpWidget(createWidget(isModerating: true));
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    final hideButton = tester.widget<OutlinedButton>(
      find.byKey(const Key('admin_review_action_hide')),
    );
    expect(hideButton.onPressed, isNull);
  });
}
