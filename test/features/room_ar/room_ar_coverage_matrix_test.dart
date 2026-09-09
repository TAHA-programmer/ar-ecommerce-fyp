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

  // The four originally physically-approved production products, plus the
  // Phase 9.2 coverage-expansion set (26 ids across 6 developer-approved GLB
  // designs — tracker §15/§33, matrix §4, 2026-09-05/09). All 30 carry valid
  // renderable `arMetadata` equal to `RoomArProductManifest.byProductId` in
  // the seed. All 30 are now LIVE and physically PHYS PASSED — the
  // individually-modelled 3 (velvet-armchair/wooden-console/marble-side-table)
  // and all 23 beige-ar-in-stock listings were modelled, approved, deployed
  // and physically verified (developer-confirmed, tracker §33).
  const approvedArIds = {
    'luna-accent-chair',
    'glass-coffee-table',
    'modern-table-lamp',
    'luna-3-seater-sofa',
    // Individually-modelled coverage-expansion products.
    'velvet-armchair',
    'wooden-console',
    'marble-side-table',
    // Beige AR Rug — one shared design, 7 listing ids.
    'beige-ar-in-stock-5',
    'beige-ar-in-stock-7',
    'beige-ar-in-stock-11',
    'beige-ar-in-stock-13',
    'beige-ar-in-stock-17',
    'beige-ar-in-stock-19',
    'beige-ar-in-stock-23',
    // Beige AR Sofa — one shared design, 8 listing ids.
    'beige-ar-in-stock-2',
    'beige-ar-in-stock-4',
    'beige-ar-in-stock-8',
    'beige-ar-in-stock-10',
    'beige-ar-in-stock-14',
    'beige-ar-in-stock-16',
    'beige-ar-in-stock-20',
    'beige-ar-in-stock-22',
    // Beige AR Vase — one shared design, 8 listing ids.
    'beige-ar-in-stock-3',
    'beige-ar-in-stock-6',
    'beige-ar-in-stock-9',
    'beige-ar-in-stock-12',
    'beige-ar-in-stock-15',
    'beige-ar-in-stock-18',
    'beige-ar-in-stock-21',
    'beige-ar-in-stock-24',
  };

  // Every real catalogue product once labelled roomAr with no model has now
  // been resolved one way or another (matrix §3.2): the 3 individually-
  // modelled ones moved into `approvedArIds` above, and
  // `minimalist-bedroom-set` (the last one) was permanently removed from the
  // catalogue by developer decision (Phase 9.2 closeout, 2026-09-09) — its
  // Firestore doc + app listing were deleted via Admin, so it no longer
  // appears in the seed at all (and must not be re-added — see
  // `mock_product_seed_data.dart`'s comment at that former entry). This set
  // is intentionally empty: kept as a named, documented placeholder in case
  // a new real-but-unmodelled roomAr product is ever added again, rather
  // than silently dropping the category from this test.
  const deferredRealArIds = <String>{};

  // Filler/demo products labelled roomAr in the SEED baseline with no
  // `arMetadata` by default (matrix §3.3) — dynamically customer-associable
  // via Admin without any seed or code change (Phase 9.2 R6's whole point).
  // `other-product-3`/`other-product-9` had the approved lamp model
  // associated through Admin AR management LIVE and now work correctly for
  // customers (developer-confirmed, tracker §33) — that association is a
  // live-Firestore-only edit and is correctly NOT reflected in this static
  // seed/mock baseline, which continues to model "before any admin
  // association" for both.
  const fillerArIds = {'other-product-3', 'other-product-9'};

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
    expect(roomArIds.length, 32);
  });

  test('only the approved products (4 original + 26 coverage-expansion) carry '
      'valid renderable AR metadata', () {
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
  });

  test('every deferred/filler roomAr product is customer-ineligible for AR in '
      'the seed baseline (a live per-product Admin association, as exercised '
      'for other-product-3/9, is a Firestore-only edit outside this static '
      'seed and is correctly not modelled here)', () {
    for (final p in all) {
      if (deferredRealArIds.contains(p.id) || fillerArIds.contains(p.id)) {
        expect(
          p.hasRenderableArModel,
          isFalse,
          reason:
              '${p.id} is roomAr but has no verified model in the seed — '
              'it must stay customer-disabled by default (durable rule 4) '
              'unless/until an admin associates one live.',
        );
      }
    }
  });
}
