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
  static const Map<String, ProductArMetadata> byProductId = {
    'luna-accent-chair': ProductArMetadata(
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
    'glass-coffee-table': ProductArMetadata(
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
    'modern-table-lamp': ProductArMetadata(
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
    'luna-3-seater-sofa': ProductArMetadata(
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
  };
}
