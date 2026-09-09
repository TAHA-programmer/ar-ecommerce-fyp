import '../../core/models/product/product_ar_metadata.dart';

/// The exact production Room-AR metadata for the four physically-approved
/// products (tracker §2.4–2.8, §4, §6).
///
/// **Reference only — nothing writes this to Firestore in the R11/R12 pass.**
/// It is the single source the later substeps consume:
///  * R10 — what object to fetch from Storage + which SHA-256 / bbox to assert;
///  * R13 (`glass-coffee-table`) / R14 (`luna-3-seater-sofa`) — the `ar*` fields
///    of the one atomic catalogue write;
///  * R15 (`luna-accent-chair`, `modern-table-lamp`) — enable the AR entry point.
///
/// The GLBs themselves stay bundled as Android assets in the Marker-AR engine
/// until R10 implements Storage delivery + caching; the `storagePath` values
/// below are the agreed *destinations*, not yet populated.
///
/// SHA-256 / dimensions are the values independently verified in the tracker
/// and confirmed byte-exact in the shipped APKs. Do not edit without a matching
/// tracker update.
class RoomArProductManifest {
  RoomArProductManifest._();

  /// Storage object path for a product's current AR model.
  static String storagePathFor(String productId, {String version = '1'}) =>
      'products/$productId/ar/model-v$version.glb';

  /// productId → the exact contract. Keyed by the **current** Firestore product
  /// ids; the coffee table / sofa *titles* change in R13/R14 but their ids do
  /// not.
  ///
  /// `final`, not `const` — the coverage-expansion groups below are built
  /// with `for` loops over the shared-design id lists, which Dart does not
  /// allow inside a const collection literal. Every individual
  /// [ProductArMetadata] value is still a `const` object.
  static final Map<String, ProductArMetadata> byProductId = {
    'luna-accent-chair': const ProductArMetadata(
      storagePath: 'products/luna-accent-chair/ar/model-v1.glb',
      format: ProductArMetadata.glbFormat,
      modelVersion: '1',
      sha256:
          'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
      widthM: 0.70,
      depthM: 0.72,
      heightM: 0.82,
      scale: 1.0,
      scaleContract: ProductArMetadata.currentScaleContract,
    ),
    'glass-coffee-table': const ProductArMetadata(
      storagePath: 'products/glass-coffee-table/ar/model-v1.glb',
      format: ProductArMetadata.glbFormat,
      modelVersion: '1',
      sha256:
          'd10f32a7373d84031d3e51b8e9770610f514f62fa56110608852f1640ab7a727',
      widthM: 0.90,
      depthM: 0.90,
      heightM: 0.42,
      scale: 1.0,
      scaleContract: ProductArMetadata.currentScaleContract,
    ),
    'modern-table-lamp': const ProductArMetadata(
      storagePath: 'products/modern-table-lamp/ar/model-v1.glb',
      format: ProductArMetadata.glbFormat,
      modelVersion: '1',
      sha256:
          'ee417ead58e72de9518358288f089bad272779c190125e01ac372fcfc16bb565',
      widthM: 0.20,
      depthM: 0.20,
      heightM: 0.45,
      scale: 1.0,
      scaleContract: ProductArMetadata.currentScaleContract,
    ),
    'luna-3-seater-sofa': const ProductArMetadata(
      storagePath: 'products/luna-3-seater-sofa/ar/model-v1.glb',
      format: ProductArMetadata.glbFormat,
      modelVersion: '1',
      sha256:
          'efd400046b265fd49d8d2b0382d378d230d625cb879740a3ef0697ca86c0d187',
      widthM: 2.65,
      depthM: 1.65,
      heightM: 0.82,
      scale: 1.0,
      scaleContract: ProductArMetadata.currentScaleContract,
    ),

    // ── Phase 9.2 coverage-expansion (tracker §15, 2026-09-05) ─────────────
    // Six developer-approved GLB designs across 26 product ids. Each id gets
    // its own Storage path even where a design is shared across a group
    // (rule 9 — a shared design still means N uploads + N metadata entries).
    // Asset approval only at authoring time; this manifest entry is the local
    // integration step — no GLB has been uploaded and no live Firestore write
    // has happened yet (see `18_ROOM_AR_PRODUCT_COVERAGE_MATRIX.md` §4).
    'velvet-armchair': const ProductArMetadata(
      storagePath: 'products/velvet-armchair/ar/model-v1.glb',
      format: ProductArMetadata.glbFormat,
      modelVersion: '1',
      sha256:
          '9909929fdc84adf526127887ab782805bee0ff6863c04e0dd1510a4264f8a09e',
      widthM: 0.72,
      depthM: 0.76,
      heightM: 0.78,
      scale: 1.0,
      scaleContract: ProductArMetadata.currentScaleContract,
    ),
    'wooden-console': const ProductArMetadata(
      storagePath: 'products/wooden-console/ar/model-v1.glb',
      format: ProductArMetadata.glbFormat,
      modelVersion: '1',
      sha256:
          'b22ac85b25cac2b4924e04793701c95907c36474bb04df7c4aa9ddda51e03433',
      widthM: 1.80,
      depthM: 0.42,
      heightM: 0.72,
      scale: 1.0,
      scaleContract: ProductArMetadata.currentScaleContract,
    ),
    'marble-side-table': const ProductArMetadata(
      storagePath: 'products/marble-side-table/ar/model-v1.glb',
      format: ProductArMetadata.glbFormat,
      modelVersion: '1',
      sha256:
          '287b8bb97b3bff21de651b49dbb46024be0462fc2ea3e49c6a08964f79b9b7b3',
      widthM: 0.46,
      depthM: 0.46,
      heightM: 0.53,
      scale: 1.0,
      scaleContract: ProductArMetadata.currentScaleContract,
    ),
    // Beige AR Rug — one shared design, 7 listing ids (matrix §3.3).
    for (final id in _beigeArRugIds)
      id: ProductArMetadata(
        storagePath: 'products/$id/ar/model-v1.glb',
        format: ProductArMetadata.glbFormat,
        modelVersion: '1',
        sha256:
            'd21f1adaf04708ff96976282fa7543814c9718028a3297fe392b0847766837e5',
        widthM: 2.00,
        depthM: 1.35,
        heightM: 0.012,
        scale: 1.0,
        scaleContract: ProductArMetadata.currentScaleContract,
      ),
    // Beige AR Sofa — one shared design, 8 listing ids (matrix §3.3).
    for (final id in _beigeArSofaIds)
      id: ProductArMetadata(
        storagePath: 'products/$id/ar/model-v1.glb',
        format: ProductArMetadata.glbFormat,
        modelVersion: '1',
        sha256:
            '5dfc2a86ea7a9c66ca4190179a31e1d2f2b28c9829cbd9b2240b9284c7db2a84',
        widthM: 2.50,
        depthM: 1.60,
        heightM: 0.70,
        scale: 1.0,
        scaleContract: ProductArMetadata.currentScaleContract,
      ),
    // Beige AR Vase — one shared design, 8 listing ids (matrix §3.3).
    for (final id in _beigeArVaseIds)
      id: ProductArMetadata(
        storagePath: 'products/$id/ar/model-v1.glb',
        format: ProductArMetadata.glbFormat,
        modelVersion: '1',
        sha256:
            'cf8c32bab30e43ca138fd07b5aca50a792389d91228aaacb05cb09321989295d',
        widthM: 0.15,
        depthM: 0.15,
        heightM: 0.20,
        scale: 1.0,
        scaleContract: ProductArMetadata.currentScaleContract,
      ),
  };

  /// `beige-ar-in-stock-{i}` ids sharing the Beige AR Rug design — must stay
  /// in lockstep with the `i % 3 == 0 → decor / elif i % 2 == 0 → furniture /
  /// else → rugs` split in `mock_product_seed_data.dart`'s coverage-expansion
  /// loop (matrix §3.3).
  static const List<String> _beigeArRugIds = [
    'beige-ar-in-stock-5',
    'beige-ar-in-stock-7',
    'beige-ar-in-stock-11',
    'beige-ar-in-stock-13',
    'beige-ar-in-stock-17',
    'beige-ar-in-stock-19',
    'beige-ar-in-stock-23',
  ];

  /// `beige-ar-in-stock-{i}` ids sharing the Beige AR Sofa design.
  static const List<String> _beigeArSofaIds = [
    'beige-ar-in-stock-2',
    'beige-ar-in-stock-4',
    'beige-ar-in-stock-8',
    'beige-ar-in-stock-10',
    'beige-ar-in-stock-14',
    'beige-ar-in-stock-16',
    'beige-ar-in-stock-20',
    'beige-ar-in-stock-22',
  ];

  /// `beige-ar-in-stock-{i}` ids sharing the Beige AR Vase design.
  static const List<String> _beigeArVaseIds = [
    'beige-ar-in-stock-3',
    'beige-ar-in-stock-6',
    'beige-ar-in-stock-9',
    'beige-ar-in-stock-12',
    'beige-ar-in-stock-15',
    'beige-ar-in-stock-18',
    'beige-ar-in-stock-21',
    'beige-ar-in-stock-24',
  ];
}
