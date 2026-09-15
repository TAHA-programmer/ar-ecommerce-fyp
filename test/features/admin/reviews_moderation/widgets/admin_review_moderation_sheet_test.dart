import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/admin/reviews_moderation/widgets/admin_review_moderation_sheet.dart';
import 'package:twin_ar/features/reviews/models/review_moderation_action.dart';
import 'package:twin_ar/features/reviews/models/review_validation.dart';

void main() {
  Widget createWidget(
    ReviewModerationAction action,
    ValueChanged<String?> onResult,
  ) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              final reason = await showAdminReviewModerationSheet(
                context,
                action: action,
              );
              onResult(reason);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );
  }

  testWidgets('shows the action label and requires a non-empty reason '
      'before Confirm is enabled', (tester) async {
    String? result = 'unset';
    await tester.pumpWidget(
      createWidget(ReviewModerationAction.hide, (r) => result = r),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Hide Review'), findsOneWidget);
    final confirmFinder = find.byKey(
      const Key('admin_review_moderation_confirm_button'),
    );
    expect(tester.widget<ElevatedButton>(confirmFinder).onPressed, isNull);

    await tester.enterText(
      find.byKey(const Key('admin_review_moderation_reason_field')),
      'Contains offensive language.',
    );
    await tester.pump();
    expect(tester.widget<ElevatedButton>(confirmFinder).onPressed, isNotNull);

    await tester.tap(confirmFinder);
    await tester.pumpAndSettle();
    expect(result, 'Contains offensive language.');
  });

  testWidgets('Cancel resolves to null without requiring a reason', (
    tester,
  ) async {
    String? result = 'unset';
    await tester.pumpWidget(
      createWidget(ReviewModerationAction.restore, (r) => result = r),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const Key('admin_review_moderation_cancel_button')),
    );
    await tester.pumpAndSettle();
    expect(result, isNull);
  });

  testWidgets('a whitespace-only reason still leaves Confirm disabled', (
    tester,
  ) async {
    await tester.pumpWidget(
      createWidget(ReviewModerationAction.reject, (_) {}),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const Key('admin_review_moderation_reason_field')),
      '   ',
    );
    await tester.pump();

    final confirmFinder = find.byKey(
      const Key('admin_review_moderation_confirm_button'),
    );
    expect(tester.widget<ElevatedButton>(confirmFinder).onPressed, isNull);
  });

  testWidgets('enforces ReviewValidation.moderationReasonMaxLength via the '
      'field\'s maxLength', (tester) async {
    await tester.pumpWidget(createWidget(ReviewModerationAction.hide, (_) {}));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    final field = tester.widget<TextField>(
      find.byKey(const Key('admin_review_moderation_reason_field')),
    );
    expect(field.maxLength, ReviewValidation.moderationReasonMaxLength);
  });
}
