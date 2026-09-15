import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';

void main() {
  group('ProductSummaryModel.copyWith (Ratings/Reviews v1 Stage 12)', () {
    const base = ProductSummaryModel(
      id: 'p1',
      title: 'Luna Accent Chair',
      imageAssetPath: 'assets/images/placeholder.png',
      currentPrice: 'Rs 12,000/-',
      rating: 4.8, // the STATIC seed value toSummaryModel() would carry
      reviewCount: 23,
      inStock: true,
      arEnabled: true,
      tryOnEnabled: false,
      arRenderable: true,
    );

    test('overwrites rating/reviewCount, leaving every other field '
        'untouched', () {
      final live = base.copyWith(rating: 0.0, reviewCount: 0);

      expect(live.rating, 0.0);
      expect(live.reviewCount, 0);
      expect(live.id, base.id);
      expect(live.title, base.title);
      expect(live.imageAssetPath, base.imageAssetPath);
      expect(live.currentPrice, base.currentPrice);
      expect(live.inStock, base.inStock);
      expect(live.arEnabled, base.arEnabled);
      expect(live.tryOnEnabled, base.tryOnEnabled);
      expect(live.arRenderable, base.arRenderable);
    });

    test('omitting a parameter keeps the original value - never silently '
        'zeroes it', () {
      final unchanged = base.copyWith();
      expect(unchanged.rating, base.rating);
      expect(unchanged.reviewCount, base.reviewCount);
    });

    test('can set rating without touching reviewCount and vice versa', () {
      expect(base.copyWith(rating: 5.0).reviewCount, base.reviewCount);
      expect(base.copyWith(reviewCount: 99).rating, base.rating);
    });
  });
}
