import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/review_report_reason.dart';
import 'package:twin_ar/features/reviews/widgets/review_report_sheet.dart';

void main() {
  Widget createWidget(ValueChanged<ReviewReportSubmission?> onResult) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final result = await showReviewReportSheet(context);
              onResult(result);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('defaults to "Spam" selected and submits it with no note', (
    tester,
  ) async {
    ReviewReportSubmission? result;
    await tester.pumpWidget(createWidget((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Report this review'), findsOneWidget);
    await tester.tap(find.byKey(const Key('review_report_submit_button')));
    await tester.pumpAndSettle();

    expect(result, isNotNull);
    expect(result!.reason, ReviewReportReason.spam);
    expect(result!.note, isNull);
  });

  testWidgets('selecting a different reason and typing a note submits both', (
    tester,
  ) async {
    ReviewReportSubmission? result;
    await tester.pumpWidget(createWidget((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('review_report_reason_chip_offensive')),
    );
    await tester.pump();
    await tester.enterText(
      find.byKey(const Key('review_report_note_field')),
      'Uses abusive language.',
    );
    await tester.tap(find.byKey(const Key('review_report_submit_button')));
    await tester.pumpAndSettle();

    expect(result!.reason, ReviewReportReason.offensive);
    expect(result!.note, 'Uses abusive language.');
  });

  testWidgets('Cancel resolves to null', (tester) async {
    ReviewReportSubmission? result = const ReviewReportSubmission(
      reason: ReviewReportReason.other,
    );
    await tester.pumpWidget(createWidget((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('review_report_cancel_button')));
    await tester.pumpAndSettle();

    expect(result, isNull);
  });

  testWidgets('a whitespace-only note submits as null, not blank text', (
    tester,
  ) async {
    ReviewReportSubmission? result;
    await tester.pumpWidget(createWidget((r) => result = r));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('review_report_note_field')),
      '   ',
    );
    await tester.tap(find.byKey(const Key('review_report_submit_button')));
    await tester.pumpAndSettle();

    expect(result!.note, isNull);
  });
}
