/// The production Room-AR model contract for a single product (Phase 9.2 R11/R12).
///
/// One immutable typed value object holding everything the runtime needs to
/// fetch, verify and render a product's GLB — replacing the pre-9.2 assumption
/// that a single bare `arModelAssetPath` string was enough. The same GLB feeds
/// all three tiers (ARCore markerless / OpenCV marker / 3D preview), so tier
/// support is not stored per product; instead [scaleContract] identifies the
/// authoring contract (`+Y up · −Z front · floor-centred · metres`, see
/// `_ar_assets/SCALE_CONTRACT.md`) that every tier consumes.
///
/// Firestore shape: flat `ar*` keys on the `products/{id}` document (consistent
/// with the existing `arModelAssetPath` / `arScale` fields). Parsing lives in
/// this class + `product_firestore_mapper.dart`; nothing above the data layer
/// touches the wire format.
///
/// Safety: [fromProductData] never throws. A document with no
/// `arModelStoragePath` yields `null` (the product simply has no AR model — a
/// normal state). A document with a *present but broken* contract yields a
/// non-`null` object whose [isRenderable] is `false`, so the runtime refuses to
/// load it rather than guessing; [validationIssues] explains why (for admin /
/// diagnostics).
class ProductArMetadata {
  /// The current scale/orientation authoring contract identifier. Bump when the
  /// `SCALE_CONTRACT.md` authoring rules change in a way that invalidates old
  /// GLBs.
  static const String currentScaleContract = 'twin-ar/scale-contract-9.2.2';

  static const String glbFormat = 'glb';

  /// Firebase Storage **object path** (never a download URL), e.g.
  /// `products/luna-accent-chair/ar/model-v1.glb`.
  final String storagePath;

  /// Container format — only `"glb"` is supported.
  final String format;

  /// Opaque model version string (e.g. `"1"`). Part of the cache key in R10.
  final String modelVersion;

  /// Lowercase hex SHA-256 (64 chars) of the exact GLB bytes — integrity check
  /// before render (R10).
  final String sha256;

  /// Real-world extents in metres. `width` = X, `depth` = Z, `height` = Y —
  /// the authoritative bounding box; the app asserts the loaded GLB matches
  /// within ±3 %.
  final double widthM;
  final double depthM;
  final double heightM;

  /// Uniform scale correction, default `1.0`. Non-`1.0` only when a sourced
  /// model genuinely cannot be re-exported at true size.
  final double scale;

  /// The authoring contract this GLB satisfies — see [currentScaleContract].
  final String scaleContract;

  const ProductArMetadata({
    required this.storagePath,
    this.format = glbFormat,
    required this.modelVersion,
    required this.sha256,
    required this.widthM,
    required this.depthM,
    required this.heightM,
    this.scale = 1.0,
    this.scaleContract = currentScaleContract,
  });

  /// `[width, depth, height]` metres.
  ({double width, double depth, double height}) get dimensionsM =>
      (width: widthM, depth: depthM, height: heightM);

  /// `true` only when every field is present and well-formed, so the runtime
  /// may safely fetch + render this model.
  bool get isRenderable => _issues(_selfMap()).isEmpty;

  // ── Firestore keys ───────────────────────────────────────────────────────
  static const _kPath = 'arModelStoragePath';
  static const _kFormat = 'arModelFormat';
  static const _kVersion = 'arModelVersion';
  static const _kSha = 'arModelSha256';
  static const _kWidth = 'arWidthM';
  static const _kDepth = 'arDepthM';
  static const _kHeight = 'arHeightM';
  static const _kScale = 'arScale';
  static const _kContract = 'arScaleContract';

  /// The `ar*` fields to merge into a `products/{id}` Firestore map.
  Map<String, dynamic> toFirestoreFields() => {
    _kPath: storagePath,
    _kFormat: format,
    _kVersion: modelVersion,
    _kSha: sha256,
    _kWidth: widthM,
    _kDepth: depthM,
    _kHeight: heightM,
    _kScale: scale,
    _kContract: scaleContract,
  };

  /// Safe string read — any non-string Firestore value (int, bool, …) becomes
  /// `''` rather than a cast error. Keeps [fromProductData] / [validationIssues]
  /// total.
  static String _str(Object? v) => v is String ? v.trim() : '';

  /// Parse from a whole `products/{id}` data map. Returns `null` when the
  /// product has no AR model at all (`arModelStoragePath` absent/blank).
  /// Otherwise returns an object that may still be non-[isRenderable] — the
  /// caller decides (see [validationIssues]). Never throws.
  static ProductArMetadata? fromProductData(Map<String, dynamic> data) {
    final path = _str(data[_kPath]);
    if (path.isEmpty) return null;
    double d(Object? v) => (v is num && v.isFinite) ? v.toDouble() : 0.0;
    return ProductArMetadata(
      storagePath: path,
      format: _str(data[_kFormat]).toLowerCase(),
      modelVersion: _str(data[_kVersion]),
      // Kept verbatim — the contract requires lowercase hex, so an
      // upper/mixed-case value is (honestly) non-renderable rather than
      // silently normalised.
      sha256: _str(data[_kSha]),
      widthM: d(data[_kWidth]),
      depthM: d(data[_kDepth]),
      heightM: d(data[_kHeight]),
      scale: (data[_kScale] is num && (data[_kScale] as num).isFinite)
          ? (data[_kScale] as num).toDouble()
          : 1.0,
      scaleContract: _str(data[_kContract]),
    );
  }

  /// Human-readable reasons the AR metadata in [data] is not usable, or `[]`
  /// when it is fully valid. `['no AR model metadata']` when there is no model
  /// at all. Pure — safe to call from anywhere (admin validation, tests,
  /// diagnostics).
  static List<String> validationIssues(Map<String, dynamic>? data) {
    if (data == null) return const ['no AR model metadata'];
    if (_str(data[_kPath]).isEmpty) return const ['no AR model metadata'];
    return _issues(data);
  }

  static final RegExp _sha256Re = RegExp(r'^[0-9a-f]{64}$');
  static final RegExp _driveLetterRe = RegExp(r'^[A-Za-z]:');

  static List<String> _issues(Map<String, dynamic> data) {
    final issues = <String>[];
    final path = _str(data[_kPath]);
    final format = _str(data[_kFormat]).toLowerCase();
    final version = _str(data[_kVersion]);
    final sha = _str(data[_kSha]);
    final contract = _str(data[_kContract]);
    num? asNum(Object? v) => (v is num && v.isFinite) ? v : null;
    final w = asNum(data[_kWidth]);
    final dp = asNum(data[_kDepth]);
    final h = asNum(data[_kHeight]);
    final sc = asNum(data[_kScale] ?? 1.0);

    // Storage path — a Firebase Storage OBJECT PATH, never a URL / OS path /
    // bundled asset / signed link.
    if (path.isEmpty) {
      issues.add('storage path is empty');
    } else {
      if (path.startsWith('http://') || path.startsWith('https://')) {
        issues.add('storage path is a URL, not a Storage object path');
      }
      if (path.contains('\\') || _driveLetterRe.hasMatch(path)) {
        issues.add('storage path looks like a Windows path');
      }
      if (path.startsWith('assets/') ||
          path.startsWith('flutter_assets/') ||
          path.startsWith('/')) {
        issues.add('storage path looks like a bundled/absolute asset path');
      }
      if (path.contains('?')) {
        issues.add('storage path carries a query string (signed URL?)');
      }
      if (!path.toLowerCase().endsWith('.glb')) {
        issues.add('storage path does not end in .glb');
      }
    }

    if (format != glbFormat) issues.add('format must be "glb" (got "$format")');
    if (version.isEmpty) issues.add('model version is missing');
    if (!_sha256Re.hasMatch(sha)) {
      issues.add('sha256 must be 64 lowercase hex characters');
    }
    if (contract.isEmpty) issues.add('scale-contract id is missing');

    bool okDim(num? v) => v != null && v > 0 && v <= 100;
    if (!okDim(w)) issues.add('arWidthM must be > 0 and <= 100');
    if (!okDim(dp)) issues.add('arDepthM must be > 0 and <= 100');
    if (!okDim(h)) issues.add('arHeightM must be > 0 and <= 100');
    if (sc == null || sc <= 0 || sc > 10) {
      issues.add('arScale must be > 0 and <= 10');
    }
    return issues;
  }

  Map<String, dynamic> _selfMap() => toFirestoreFields();

  ProductArMetadata copyWith({
    String? storagePath,
    String? format,
    String? modelVersion,
    String? sha256,
    double? widthM,
    double? depthM,
    double? heightM,
    double? scale,
    String? scaleContract,
  }) => ProductArMetadata(
    storagePath: storagePath ?? this.storagePath,
    format: format ?? this.format,
    modelVersion: modelVersion ?? this.modelVersion,
    sha256: sha256 ?? this.sha256,
    widthM: widthM ?? this.widthM,
    depthM: depthM ?? this.depthM,
    heightM: heightM ?? this.heightM,
    scale: scale ?? this.scale,
    scaleContract: scaleContract ?? this.scaleContract,
  );

  @override
  bool operator ==(Object other) =>
      other is ProductArMetadata &&
      other.storagePath == storagePath &&
      other.format == format &&
      other.modelVersion == modelVersion &&
      other.sha256 == sha256 &&
      other.widthM == widthM &&
      other.depthM == depthM &&
      other.heightM == heightM &&
      other.scale == scale &&
      other.scaleContract == scaleContract;

  @override
  int get hashCode => Object.hash(
    storagePath,
    format,
    modelVersion,
    sha256,
    widthM,
    depthM,
    heightM,
    scale,
    scaleContract,
  );

  @override
  String toString() =>
      'ProductArMetadata($storagePath v$modelVersion '
      '${widthM}x${depthM}x${heightM}m sha ${sha256.substring(0, sha256.length.clamp(0, 8))} '
      'renderable=$isRenderable)';
}
