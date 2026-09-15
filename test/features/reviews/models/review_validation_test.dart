import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/models/review_validation.dart';

void main() {
  group('ReviewValidation.isRatingValid', () {
    test('accepts 1 through 5', () {
      for (var i = 1; i <= 5; i++) {
        expect(ReviewValidation.isRatingValid(i), true, reason: '$i');
      }
    });

    test('rejects 0, negative, and above 5', () {
      expect(ReviewValidation.isRatingValid(0), false);
      expect(ReviewValidation.isRatingValid(-1), false);
      expect(ReviewValidation.isRatingValid(6), false);
    });
  });

  group('ReviewValidation.isTitleValid', () {
    test('null title is valid (optional)', () {
      expect(ReviewValidation.isTitleValid(null), true);
    });

    test('accepts exactly maxTitleLength, rejects one over', () {
      final atLimit = 'a' * ReviewValidation.maxTitleLength;
      final overLimit = 'a' * (ReviewValidation.maxTitleLength + 1);
      expect(ReviewValidation.isTitleValid(atLimit), true);
      expect(ReviewValidation.isTitleValid(overLimit), false);
    });
  });

  group('ReviewValidation.isBodyValid', () {
    test('rejects below minBodyLength', () {
      final tooShort = 'a' * (ReviewValidation.minBodyLength - 1);
      expect(ReviewValidation.isBodyValid(tooShort), false);
    });

    test('accepts exactly minBodyLength and maxBodyLength', () {
      expect(
        ReviewValidation.isBodyValid('a' * ReviewValidation.minBodyLength),
        true,
      );
      expect(
        ReviewValidation.isBodyValid('a' * ReviewValidation.maxBodyLength),
        true,
      );
    });

    test('rejects above maxBodyLength', () {
      final tooLong = 'a' * (ReviewValidation.maxBodyLength + 1);
      expect(ReviewValidation.isBodyValid(tooLong), false);
    });
  });

  group('ReviewValidation.isReportNoteValid', () {
    test('null note is valid (optional)', () {
      expect(ReviewValidation.isReportNoteValid(null), true);
    });

    test('accepts exactly reportNoteMaxLength, rejects one over', () {
      final atLimit = 'a' * ReviewValidation.reportNoteMaxLength;
      final overLimit = 'a' * (ReviewValidation.reportNoteMaxLength + 1);
      expect(ReviewValidation.isReportNoteValid(atLimit), true);
      expect(ReviewValidation.isReportNoteValid(overLimit), false);
    });
  });

  group('ReviewValidation.isModerationReasonValid', () {
    test('rejects an empty or whitespace-only reason - required for EVERY '
        'action, including restore', () {
      expect(ReviewValidation.isModerationReasonValid(''), false);
      expect(ReviewValidation.isModerationReasonValid('   '), false);
    });

    test('accepts a real reason', () {
      expect(
        ReviewValidation.isModerationReasonValid('Contains profanity.'),
        true,
      );
    });

    test('accepts exactly moderationReasonMaxLength, rejects one over', () {
      final atLimit = 'a' * ReviewValidation.moderationReasonMaxLength;
      final overLimit = 'a' * (ReviewValidation.moderationReasonMaxLength + 1);
      expect(ReviewValidation.isModerationReasonValid(atLimit), true);
      expect(ReviewValidation.isModerationReasonValid(overLimit), false);
    });
  });
}
