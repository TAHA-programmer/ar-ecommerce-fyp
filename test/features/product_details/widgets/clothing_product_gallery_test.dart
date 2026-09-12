import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/features/product_details/widgets/clothing_product_gallery.dart';

void main() {
  Widget harness({
    required ProductExperienceType experienceType,
    required bool hasRenderableVtoAsset,
  }) {
    return MaterialApp(
      home: Scaffold(
        body: ClothingProductGallery(
          gallery: const [ProductImageRef(path: 'assets/x.png')],
          activeIndex: 0,
          onThumbnailTap: (_) {},
          experienceType: experienceType,
          hasRenderableVtoAsset: hasRenderableVtoAsset,
        ),
      ),
    );
  }

  testWidgets('shows the TRY-ON badge for an eligible Virtual Try-On product', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        experienceType: ProductExperienceType.virtualTryOn,
        hasRenderableVtoAsset: true,
      ),
    );

    expect(find.text('TRY-ON'), findsOneWidget);
  });

  testWidgets(
    'Phase 9.3 Stage 6 — hides the TRY-ON badge for a virtualTryOn product '
    'with no renderable asset (not configured yet, or admin-disabled) '
    'instead of advertising a try-on that cannot launch',
    (tester) async {
      await tester.pumpWidget(
        harness(
          experienceType: ProductExperienceType.virtualTryOn,
          hasRenderableVtoAsset: false,
        ),
      );

      expect(find.text('TRY-ON'), findsNothing);
    },
  );

  testWidgets('non-VTO products never show the badge regardless of the flag', (
    tester,
  ) async {
    await tester.pumpWidget(
      harness(
        experienceType: ProductExperienceType.none,
        hasRenderableVtoAsset: true,
      ),
    );

    expect(find.text('TRY-ON'), findsNothing);
  });
}
