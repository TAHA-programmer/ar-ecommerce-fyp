import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/features/product_details/widgets/product_details_bottom_actions.dart';

void main() {
  Widget harness({
    required ProductExperienceType experienceType,
    required bool hasRenderableVtoAsset,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ProductDetailsBottomActions(
          experienceType: experienceType,
          price: '\$10.00',
          hasRenderableVtoAsset: hasRenderableVtoAsset,
          onAddToCart: () {},
          onViewInRoom: () {},
          onTryItOn: () {},
        ),
      ),
    );
  }

  testWidgets('shows "Try It On" for an eligible Virtual Try-On product', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        experienceType: ProductExperienceType.virtualTryOn,
        hasRenderableVtoAsset: true,
      ),
    );

    expect(find.text('Try It On'), findsOneWidget);
    expect(find.text('Add to Cart'), findsOneWidget);
  });

  testWidgets(
    'Phase 9.3 Stage 5 — hides "Try It On" for a virtualTryOn product with '
    'no renderable asset (not configured yet, or admin-disabled) instead of '
    'a dead button',
    (tester) async {
      await tester.pumpWidget(
        harness(
          experienceType: ProductExperienceType.virtualTryOn,
          hasRenderableVtoAsset: false,
        ),
      );

      expect(find.text('Try It On'), findsNothing);
      // Falls back to a plain Add to Cart action, same as a non-AR product.
      expect(find.text('Add to Cart'), findsOneWidget);
    },
  );

  testWidgets('Room AR products are unaffected by the VTO gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        experienceType: ProductExperienceType.roomAr,
        hasRenderableVtoAsset: false,
      ),
    );

    expect(find.text('View in Your Room'), findsOneWidget);
    expect(find.text('Add to Cart'), findsOneWidget);
  });
}
