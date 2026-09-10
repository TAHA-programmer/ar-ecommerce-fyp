import 'dart:io';

import '../../../../core/models/product/product_vto_metadata.dart';

/// A locally-picked, signature-validated Virtual Try-On garment image the admin
/// has staged for one slot but not yet uploaded (Phase 9.3 Stage 3).
///
/// The 2-D sibling of [AdminArModelCandidate]. Everything here is derived from
/// the file's own bytes — [sha256], [sizeBytes], [contentType], [width] and
/// [height] come from `inspectVtoGarmentFile`, never from the OS/picker
/// metadata. Nothing reaches Storage until the screen's Save.
class AdminVtoGarmentCandidate {
  AdminVtoGarmentCandidate({
    required this.file,
    required this.slot,
    required this.sizeBytes,
    required this.sha256,
    required this.contentType,
    required this.width,
    required this.height,
    required this.targetVersion,
  });

  /// The picked file on device — the upload source and the inline preview
  /// source.
  final File file;

  /// `'default'` for the product-wide asset, or a `ProductColorOption.name`
  /// (`'black'`, `'blue'`, …) for a per-colour asset.
  final String slot;

  final int sizeBytes;

  /// Lowercase-hex SHA-256 of the exact file bytes.
  final String sha256;

  /// `image/jpeg` or `image/png`, decided from the file signature.
  final String contentType;

  final int width;
  final int height;

  /// The `garment-{slot}-v{n}` this candidate will become — `previousVersion + 1`
  /// for that slot, or `1` when the slot has no committed asset.
  final int targetVersion;

  double get sizeMib => sizeBytes / (1024 * 1024);

  String get fileExtension => contentType == 'image/png' ? 'png' : 'jpg';

  int get longestEdgePx => width >= height ? width : height;

  bool get isBelowRecommendedResolution =>
      longestEdgePx < VtoGarmentAsset.recommendedMinLongEdgePx;

  bool get isDefaultSlot => slot == 'default';

  /// The exact Storage object path this candidate uploads to for [productId] —
  /// the single source of truth for the object name and for the Firestore
  /// pointer. Always matches [VtoGarmentAsset.matchesExpectedPath].
  String storagePathFor(String productId) =>
      'products/$productId/vto/garment-$slot-v$targetVersion.$fileExtension';

  /// The `twinArVto*` provenance custom-metadata for the upload — shape-parallel
  /// to Room-AR's `twinArAr*` set, so `storage.rules` can require the SHA key
  /// on every VTO-object write.
  Map<String, String> provenance() => {
    'twinArVtoSha256': sha256,
    'twinArVtoVersion': '$targetVersion',
    'twinArVtoWidth': '$width',
    'twinArVtoHeight': '$height',
    'twinArVtoContentType': contentType,
  };

  /// The production asset this candidate becomes once uploaded to [storagePath].
  VtoGarmentAsset toAsset({required String storagePath}) => VtoGarmentAsset(
    storagePath: storagePath,
    sha256: sha256,
    contentType: contentType,
    byteSize: sizeBytes,
    width: width,
    height: height,
    version: targetVersion,
  );
}
