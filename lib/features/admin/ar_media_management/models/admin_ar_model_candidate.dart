import 'dart:io';

import '../../../../core/models/product/product_ar_metadata.dart';

/// A locally-picked, structurally-validated Room-AR GLB that the admin has
/// staged but not yet uploaded (Phase 9.2 R16).
///
/// Mirrors how a device photo stages as `ProductImageRef(source: .file)` and
/// only reaches Storage on Save. Everything here is derived from the file's
/// own bytes — [sha256], [sizeBytes] and [measuredM] come from
/// `inspectArGlbFile`, never from the OS/picker metadata.
class AdminArModelCandidate {
  AdminArModelCandidate({
    required this.file,
    required this.sizeBytes,
    required this.sha256,
    required this.measuredM,
    required this.floorCentred,
    required this.widthM,
    required this.depthM,
    required this.heightM,
    required this.scale,
    required this.targetVersion,
  });

  /// The picked file on device — the upload source and the preview source.
  final File file;

  final int sizeBytes;

  /// Lowercase-hex SHA-256 of the exact file bytes.
  final String sha256;

  /// World-space extents measured from the mesh data (X, Z, Y).
  final ({double width, double depth, double height}) measuredM;

  final bool floorCentred;

  /// The dimensions the admin has captured/confirmed (default = [measuredM]).
  /// These are what gets written to Firestore; the GLB is re-checked against
  /// them (±3 % / ±2 cm) before any upload.
  final double widthM;
  final double depthM;
  final double heightM;

  /// Uniform scale correction (default 1.0).
  final double scale;

  /// The `model-v{n}` this candidate will become — `previousVersion + 1`, or
  /// `1` when the product has no committed model.
  final int targetVersion;

  double get sizeMib => sizeBytes / (1024 * 1024);

  bool get dimensionsMatchMeasured =>
      _close(widthM, measuredM.width) &&
      _close(depthM, measuredM.depth) &&
      _close(heightM, measuredM.height);

  static bool _close(double a, double b) {
    final tol = (b * 0.03).abs();
    return (a - b).abs() <= (tol < 0.02 ? 0.02 : tol);
  }

  AdminArModelCandidate copyWith({
    double? widthM,
    double? depthM,
    double? heightM,
    double? scale,
  }) => AdminArModelCandidate(
    file: file,
    sizeBytes: sizeBytes,
    sha256: sha256,
    measuredM: measuredM,
    floorCentred: floorCentred,
    widthM: widthM ?? this.widthM,
    depthM: depthM ?? this.depthM,
    heightM: heightM ?? this.heightM,
    scale: scale ?? this.scale,
    targetVersion: targetVersion,
  );

  /// The production contract this candidate becomes once uploaded to
  /// [storagePath]. [storagePath] is supplied by the caller (it needs the real
  /// product id, which for a brand-new product is only known at save time).
  ProductArMetadata toMetadata({required String storagePath}) =>
      ProductArMetadata(
        storagePath: storagePath,
        format: ProductArMetadata.glbFormat,
        modelVersion: '$targetVersion',
        sha256: sha256,
        widthM: widthM,
        depthM: depthM,
        heightM: heightM,
        scale: scale,
        scaleContract: ProductArMetadata.currentScaleContract,
      );
}
