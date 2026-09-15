import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/reviews/utils/review_author_display_name.dart';

void main() {
  group('maskReviewerDisplayName', () {
    test('masks a two-part name to "First L."', () {
      expect(maskReviewerDisplayName('Ayesha Khan'), 'Ayesha K.');
    });

    test('masks a name with a middle name using the LAST part\'s initial', () {
      expect(maskReviewerDisplayName('Ali Raza Malik'), 'Ali M.');
    });

    test('a single-word name is shown as-is', () {
      expect(maskReviewerDisplayName('Cher'), 'Cher');
    });

    test('extra internal whitespace is collapsed', () {
      expect(maskReviewerDisplayName('  Ayesha   Khan  '), 'Ayesha K.');
    });

    test('null falls back to the safe default', () {
      expect(maskReviewerDisplayName(null), kFallbackReviewerDisplayName);
    });

    test('empty/whitespace-only falls back to the safe default', () {
      expect(maskReviewerDisplayName(''), kFallbackReviewerDisplayName);
      expect(maskReviewerDisplayName('   '), kFallbackReviewerDisplayName);
    });

    test('never reveals more than a first name + one initial', () {
      final masked = maskReviewerDisplayName('Fatima Zahra Bibi Sultana');
      expect(masked, 'Fatima S.');
      expect(masked.contains('Zahra'), false);
      expect(masked.contains('Bibi'), false);
    });
  });
}
