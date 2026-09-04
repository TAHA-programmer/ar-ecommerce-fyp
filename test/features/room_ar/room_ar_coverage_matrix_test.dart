import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_product_seed_data.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/features/room_ar/room_ar_product_manifest.dart';

/// Phase 9.2 R14 — the completion gate for
/// `twin_ar_antigravity_reference_pack/18_ROOM_AR_PRODUCT_COVERAGE_MATRIX.md`.
///
/// If a NEW product is given `experienceType: roomAr` in the seed, or one of
/// the four approved products loses/changes its `arMetadata`, this test fails —
/// forcing the coverage matrix (and the customer-eligibility decision) to be
/// updated rather than silently forgotten.
void main() {
  final all = buildMockProductSeedData();

  // The four physically-approved production products.
  const approvedArIds = {
    'luna-accent-chair',
    'glass-coffee-table',
    'modern-table-lamp',
    'luna-3-seater-sofa',
  };

  // Real catalogue products labelled roomAr with no model yet (matrix §3.2).
  const deferredRealArIds = {
    'velvet-armchair',
    'wooden-console',
    'marble-side-table',
    'minimalist-bedroom-set',
  };

  // Filler/demo products labelled roomAr, no AR intended (matrix §3.3).
  final fillerArIds = <String>{
    for (var i = 2; i <= 24; i++) 'beige-ar-in-stock-$i',
    'other-product-3',
    'other-product-9',
  };

  test('exactly the documented set of products is labelled roomAr', () {
    final roomArIds = all
        .where((p) => p.experienceType == ProductExperienceType.roomAr)
        .map((p) => p.id)
        .toSet();

    final documented = {...approvedArIds, ...deferredRealArIds, ...fillerArIds};

    final undocumented = roomArIds.difference(documented);
    final missing = documented.difference(roomArIds);

    expect(
      undocumented,
      isEmpty,
      reason:
          'New roomAr product(s) not in 18_ROOM_AR_PRODUCT_COVERAGE_MATRIX.md: '
          '$undocumented — add them to the matrix and decide customer '
          'eligibility (approve a model, or recast experienceType to none).',
    );
    expect(
      missing,
      isEmpty,
      reason: 'Matrix lists roomAr products no longer in the seed: $missing',
    );
    expect(roomArIds.length, 33);
  });

  test(
    'only the four approved products carry valid renderable AR metadata',
    () {
      for (final p in all) {
        if (approvedArIds.contains(p.id)) {
          expect(p.arMetadata, isNotNull, reason: p.id);
          expect(p.arMetadata!.isRenderable, isTrue, reason: p.id);
          expect(p.hasRenderableArModel, isTrue, reason: p.id);
          expect(
            p.arMetadata,
            RoomArProductManifest.byProductId[p.id],
            reason: '${p.id}: seed arMetadata must equal the manifest',
          );
        } else {
          expect(p.arMetadata, isNull, reason: p.id);
          expect(p.hasRenderableArModel, isFalse, reason: p.id);
        }
      }
    },
  );

  test(
    'every deferred/filler roomAr product is customer-ineligible for AR',
    () {
      for (final p in all) {
        if (deferredRealArIds.contains(p.id) || fillerArIds.contains(p.id)) {
          expect(
            p.hasRenderableArModel,
            isFalse,
            reason:
                '${p.id} is roomAr but has no verified model — it must stay '
                'customer-disabled (durable rule 4).',
          );
        }
      }
    },
  );
}
