import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/review_moderation_action.dart';
import 'package:twin_ar/features/reviews/models/review_status.dart';

void main() {
  group('ReviewModerationAction.wireValue', () {
    test('matches functions/src/lib/reviews/validation.ts MODERATION_ACTIONS '
        'exactly', () {
      expect(ReviewModerationAction.hide.wireValue, 'hide');
      expect(ReviewModerationAction.restore.wireValue, 'restore');
      expect(ReviewModerationAction.reject.wireValue, 'reject');
    });
  });

  group('ReviewModerationAction.targetStatus', () {
    test('hide -> hidden, restore -> published, reject -> rejected - the '
        'same mapping moderateReview.ts uses server-side', () {
      expect(ReviewModerationAction.hide.targetStatus, ReviewStatus.hidden);
      expect(
        ReviewModerationAction.restore.targetStatus,
        ReviewStatus.published,
      );
      expect(ReviewModerationAction.reject.targetStatus, ReviewStatus.rejected);
    });
  });

  group('ReviewModerationAction.label', () {
    test('every action has a distinct, human-readable label', () {
      final labels = ReviewModerationAction.values.map((a) => a.label).toSet();
      expect(labels.length, ReviewModerationAction.values.length);
      for (final label in labels) {
        expect(label, isNotEmpty);
      }
    });
  });
}
