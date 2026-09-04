import 'dart:convert';
import 'dart:math' as math;
import 'dart:typed_data';

// Pure, dependency-free structural + dimensional validation of a `.glb`
// (glTF 2.0 binary) file, used by RoomArModelService before any bytes are
// handed to Filament (Phase 9.2 R10).
//
// This never trusts a filename, a MIME type or "Firebase said the download
// succeeded". It re-derives everything from the bytes themselves:
//  * the 12-byte GLB header (`glTF` magic, container version `2`, declared
//    total length vs. the real byte length);
//  * the chunk table — a JSON chunk (`0x4E4F534A`) that fully parses, and an
//    optional BIN chunk (`0x004E4942`), both wholly inside the file with no
//    trailing slack;
//  * the model's real-world bounding box, walking the default scene graph,
//    accumulating each node's TRS (or `matrix`) transform, and unioning the
//    world-space extents of every mesh primitive's `POSITION` accessor
//    (`min`/`max` are mandatory for `POSITION` in glTF 2.0).
//
// The bounding box is compared against the authoritative
// `arWidthM / arDepthM / arHeightM` from ProductArMetadata — width = X,
// depth = Z, height = Y, matching `_ar_assets/SCALE_CONTRACT.md`. A mismatch is
// a hard rejection, never a silent rescale.

/// The tolerance the loaded GLB's bounding box may differ from the declared
/// metadata dimensions: the larger of ±3 % or ±2 cm per axis. Mirrors
/// `_ar_assets/scripts/validate.mjs` and tracker §6.
const double kGlbDimToleranceFraction = 0.03;
const double kGlbDimToleranceMetres = 0.02;

/// How far the model's base may sit off the marker floor plane (`min-Y`) before
/// it is considered not floor-centred. Generous — this catches a model authored
/// with its origin at the centre or the ceiling, not sub-cm noise.
const double kGlbFloorOffsetToleranceM = 0.05;

/// Outcome of [GlbInspector.inspect]. Either [ok] with the measured
/// [dimensionsM], or a single customer-neutral [rejectionReason] naming the
/// first failed check (kept terse; full detail is logged, not shown).
class GlbInspectionResult {
  const GlbInspectionResult._({
    required this.ok,
    this.rejectionReason,
    this.width = 0,
    this.depth = 0,
    this.height = 0,
    this.minY = 0,
  });

  final bool ok;

  /// Non-null exactly when [ok] is false. A short machine-stable slug-ish
  /// phrase (e.g. `'not a glb (bad magic)'`, `'bounding box mismatch'`).
  final String? rejectionReason;

  /// Measured world-space extents in metres (X, Z, Y). Zero when [ok] is false
  /// and the failure happened before the box could be measured.
  final double width;
  final double depth;
  final double height;

  /// Measured world-space `min-Y` (should be ≈ 0 for a floor-centred asset).
  final double minY;

  ({double width, double depth, double height}) get dimensionsM =>
      (width: width, depth: depth, height: height);

  static GlbInspectionResult reject(String reason) =>
      GlbInspectionResult._(ok: false, rejectionReason: reason);
}

/// The declared, authoritative dimensions a GLB must match (from
/// `ProductArMetadata`). Kept as a tiny record-like class so [GlbInspector] has
/// no dependency on the metadata model.
class GlbExpectedBox {
  const GlbExpectedBox({
    required this.widthM,
    required this.depthM,
    required this.heightM,
  });

  final double widthM; // X
  final double depthM; // Z
  final double heightM; // Y
}

class GlbInspector {
  const GlbInspector();

  static const int _glbMagic = 0x46546C67; // "glTF" little-endian
  static const int _chunkJson = 0x4E4F534A; // "JSON"
  static const int _chunkBin = 0x004E4942; // "BIN\0"

  /// Full structural check + (when [expected] is given) the bounding-box match.
  /// [maxBytes], when set, rejects anything larger before parsing — a cheap
  /// guard so a wrong/huge object can't drive the JSON parser.
  GlbInspectionResult inspect(
    Uint8List bytes, {
    GlbExpectedBox? expected,
    int? maxBytes,
  }) {
    final parsed = _parseStructure(bytes, maxBytes);
    if (parsed.rejection != null) {
      return GlbInspectionResult.reject(parsed.rejection!);
    }
    final gltf = parsed.gltf!;

    if (expected == null) {
      return const GlbInspectionResult._(ok: true);
    }

    // ── bounding box ───────────────────────────────────────────────────────
    final box = _worldBoundingBox(gltf);
    if (box == null) {
      return GlbInspectionResult.reject('cannot measure bounding box');
    }
    final measuredX = box.maxX - box.minX;
    final measuredY = box.maxY - box.minY;
    final measuredZ = box.maxZ - box.minZ;

    bool within(double measured, double declared) {
      final tol = math.max(
        declared * kGlbDimToleranceFraction,
        kGlbDimToleranceMetres,
      );
      return (measured - declared).abs() <= tol;
    }

    if (!within(measuredX, expected.widthM) ||
        !within(measuredZ, expected.depthM) ||
        !within(measuredY, expected.heightM)) {
      return GlbInspectionResult._(
        ok: false,
        rejectionReason: 'bounding box does not match declared dimensions',
        width: measuredX,
        depth: measuredZ,
        height: measuredY,
        minY: box.minY,
      );
    }
    if (box.minY.abs() > kGlbFloorOffsetToleranceM) {
      return GlbInspectionResult._(
        ok: false,
        rejectionReason: 'model is not floor-centred',
        width: measuredX,
        depth: measuredZ,
        height: measuredY,
        minY: box.minY,
      );
    }

    return GlbInspectionResult._(
      ok: true,
      width: measuredX,
      depth: measuredZ,
      height: measuredY,
      minY: box.minY,
    );
  }

  /// Phase 9.2 R16 — structural validation **plus** the measured world-space
  /// bounding box, with no declared dimensions to compare against. The admin
  /// GLB-upload flow uses this to (a) reject a non-GLB / corrupt / multi-file
  /// asset up front and (b) pre-fill the width / depth / height capture fields
  /// from the model itself so the admin confirms real numbers rather than
  /// guessing. `dimensionsM` is `(0,0,0)` and `minY` `0` only when [ok] is
  /// false or the scene graph carries no measurable geometry.
  GlbMeasurement measure(Uint8List bytes, {int? maxBytes}) {
    final parsed = _parseStructure(bytes, maxBytes);
    if (parsed.rejection != null) {
      return GlbMeasurement._(ok: false, rejectionReason: parsed.rejection);
    }
    final box = _worldBoundingBox(parsed.gltf!);
    if (box == null) {
      return const GlbMeasurement._(
        ok: false,
        rejectionReason: 'cannot measure bounding box',
      );
    }
    return GlbMeasurement._(
      ok: true,
      width: box.maxX - box.minX,
      depth: box.maxZ - box.minZ,
      height: box.maxY - box.minY,
      minY: box.minY,
    );
  }

  /// Header + chunk-table + glТF-JSON structural checks shared by [inspect] and
  /// [measure]. Returns the parsed glTF map, or the first rejection reason.
  _ParsedGlb _parseStructure(Uint8List bytes, int? maxBytes) {
    if (maxBytes != null && bytes.length > maxBytes) {
      return const _ParsedGlb.reject('file exceeds maximum size');
    }
    if (bytes.length < 12 + 8) {
      return const _ParsedGlb.reject('file too small to be a glb');
    }

    final data = ByteData.sublistView(bytes);
    if (data.getUint32(0, Endian.little) != _glbMagic) {
      return const _ParsedGlb.reject('not a glb (bad magic bytes)');
    }
    final version = data.getUint32(4, Endian.little);
    if (version != 2) {
      return const _ParsedGlb.reject('unsupported glb container version');
    }
    final declaredLength = data.getUint32(8, Endian.little);
    if (declaredLength != bytes.length) {
      return const _ParsedGlb.reject(
        'declared length does not match file (truncated or padded)',
      );
    }

    // ── chunk table ────────────────────────────────────────────────────────
    int offset = 12;
    Uint8List? jsonChunk;
    bool sawBin = false;
    while (offset + 8 <= bytes.length) {
      final chunkLength = data.getUint32(offset, Endian.little);
      final chunkType = data.getUint32(offset + 4, Endian.little);
      final dataStart = offset + 8;
      final dataEnd = dataStart + chunkLength;
      if (chunkLength < 0 || dataEnd > bytes.length) {
        return const _ParsedGlb.reject('chunk overruns the file');
      }
      if (chunkType == _chunkJson) {
        if (jsonChunk != null) {
          return const _ParsedGlb.reject('duplicate JSON chunk');
        }
        jsonChunk = Uint8List.sublistView(bytes, dataStart, dataEnd);
      } else if (chunkType == _chunkBin) {
        sawBin = true;
      }
      // Unknown chunk types are legal and ignored per spec.
      offset = dataEnd;
    }
    if (offset != bytes.length) {
      return const _ParsedGlb.reject('trailing bytes after last chunk');
    }
    if (jsonChunk == null) {
      return const _ParsedGlb.reject('no JSON chunk');
    }

    Map<String, dynamic> gltf;
    try {
      final decoded = json.decode(utf8.decode(jsonChunk));
      if (decoded is! Map<String, dynamic>) {
        return const _ParsedGlb.reject('glTF JSON is not an object');
      }
      gltf = decoded;
    } catch (_) {
      return const _ParsedGlb.reject('glTF JSON does not parse');
    }

    final asset = gltf['asset'];
    if (asset is! Map || (asset['version']?.toString() ?? '') != '2.0') {
      return const _ParsedGlb.reject('glTF asset version is not 2.0');
    }
    // A single self-contained file: no external buffers (`uri`), and if the
    // JSON references binary data at all there must be a BIN chunk.
    final buffers = (gltf['buffers'] as List?) ?? const [];
    for (final b in buffers) {
      if (b is Map && b['uri'] != null) {
        return const _ParsedGlb.reject('references an external buffer');
      }
    }
    if (buffers.isNotEmpty && !sawBin) {
      return const _ParsedGlb.reject('buffer declared but no BIN chunk');
    }
    return _ParsedGlb.ok(gltf);
  }

  // ── scene-graph bounding box ─────────────────────────────────────────────

  _Aabb? _worldBoundingBox(Map<String, dynamic> gltf) {
    final nodes = (gltf['nodes'] as List?) ?? const [];
    final meshes = (gltf['meshes'] as List?) ?? const [];
    final accessors = (gltf['accessors'] as List?) ?? const [];
    final scenes = (gltf['scenes'] as List?) ?? const [];
    if (nodes.isEmpty || meshes.isEmpty || accessors.isEmpty) return null;

    final sceneIndex = (gltf['scene'] as num?)?.toInt() ?? 0;
    List<int> roots;
    if (sceneIndex >= 0 &&
        sceneIndex < scenes.length &&
        scenes[sceneIndex] is Map &&
        (scenes[sceneIndex] as Map)['nodes'] is List) {
      roots = ((scenes[sceneIndex] as Map)['nodes'] as List)
          .map((e) => (e as num).toInt())
          .toList();
    } else {
      roots = List<int>.generate(nodes.length, (i) => i);
    }

    final aabb = _Aabb();
    var measuredAny = false;

    void visit(int nodeIndex, Float64List parent) {
      if (nodeIndex < 0 || nodeIndex >= nodes.length) return;
      final node = nodes[nodeIndex];
      if (node is! Map) return;
      final local = _nodeMatrix(node);
      final world = _mul(parent, local);

      final meshIndex = (node['mesh'] as num?)?.toInt();
      if (meshIndex != null && meshIndex >= 0 && meshIndex < meshes.length) {
        final mesh = meshes[meshIndex];
        final primitives =
            (mesh is Map ? mesh['primitives'] as List? : null) ?? const [];
        for (final p in primitives) {
          if (p is! Map) continue;
          final attrs = p['attributes'];
          if (attrs is! Map) continue;
          final posIndex = (attrs['POSITION'] as num?)?.toInt();
          if (posIndex == null ||
              posIndex < 0 ||
              posIndex >= accessors.length) {
            continue;
          }
          final acc = accessors[posIndex];
          if (acc is! Map) continue;
          final min = (acc['min'] as List?)?.map((e) => (e as num).toDouble());
          final max = (acc['max'] as List?)?.map((e) => (e as num).toDouble());
          if (min == null || max == null) continue;
          final lo = min.toList();
          final hi = max.toList();
          if (lo.length < 3 || hi.length < 3) continue;
          // Transform the 8 corners of the local accessor box into world space.
          for (var i = 0; i < 8; i++) {
            final x = (i & 1) == 0 ? lo[0] : hi[0];
            final y = (i & 2) == 0 ? lo[1] : hi[1];
            final z = (i & 4) == 0 ? lo[2] : hi[2];
            final w = _transformPoint(world, x, y, z);
            aabb.add(w[0], w[1], w[2]);
            measuredAny = true;
          }
        }
      }

      final children = (node['children'] as List?) ?? const [];
      for (final c in children) {
        visit((c as num).toInt(), world);
      }
    }

    for (final r in roots) {
      visit(r, _identity());
    }
    return measuredAny ? aabb : null;
  }

  Float64List _identity() {
    final m = Float64List(16);
    m[0] = m[5] = m[10] = m[15] = 1.0;
    return m;
  }

  /// A node's local transform: `matrix` (column-major 16) when present,
  /// otherwise `T * R * S` from `translation` / `rotation` (quaternion x,y,z,w) /
  /// `scale`.
  Float64List _nodeMatrix(Map node) {
    final matrix = node['matrix'];
    if (matrix is List && matrix.length == 16) {
      final m = Float64List(16);
      for (var i = 0; i < 16; i++) {
        m[i] = (matrix[i] as num).toDouble();
      }
      return m;
    }
    final t = (node['translation'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList();
    final r = (node['rotation'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList();
    final s = (node['scale'] as List?)
        ?.map((e) => (e as num).toDouble())
        .toList();

    final tx = t != null && t.length == 3 ? t[0] : 0.0;
    final ty = t != null && t.length == 3 ? t[1] : 0.0;
    final tz = t != null && t.length == 3 ? t[2] : 0.0;
    final qx = r != null && r.length == 4 ? r[0] : 0.0;
    final qy = r != null && r.length == 4 ? r[1] : 0.0;
    final qz = r != null && r.length == 4 ? r[2] : 0.0;
    final qw = r != null && r.length == 4 ? r[3] : 1.0;
    final sx = s != null && s.length == 3 ? s[0] : 1.0;
    final sy = s != null && s.length == 3 ? s[1] : 1.0;
    final sz = s != null && s.length == 3 ? s[2] : 1.0;

    // Column-major rotation from a normalised quaternion.
    final n = math.sqrt(qx * qx + qy * qy + qz * qz + qw * qw);
    final ux = n == 0 ? 0.0 : qx / n;
    final uy = n == 0 ? 0.0 : qy / n;
    final uz = n == 0 ? 0.0 : qz / n;
    final uw = n == 0 ? 1.0 : qw / n;
    final xx = ux * ux, yy = uy * uy, zz = uz * uz;
    final xy = ux * uy, xz = ux * uz, yz = uy * uz;
    final wx = uw * ux, wy = uw * uy, wz = uw * uz;

    final m = Float64List(16);
    m[0] = (1 - 2 * (yy + zz)) * sx;
    m[1] = (2 * (xy + wz)) * sx;
    m[2] = (2 * (xz - wy)) * sx;
    m[3] = 0;
    m[4] = (2 * (xy - wz)) * sy;
    m[5] = (1 - 2 * (xx + zz)) * sy;
    m[6] = (2 * (yz + wx)) * sy;
    m[7] = 0;
    m[8] = (2 * (xz + wy)) * sz;
    m[9] = (2 * (yz - wx)) * sz;
    m[10] = (1 - 2 * (xx + yy)) * sz;
    m[11] = 0;
    m[12] = tx;
    m[13] = ty;
    m[14] = tz;
    m[15] = 1;
    return m;
  }

  /// Column-major 4×4 multiply: `a * b`.
  Float64List _mul(Float64List a, Float64List b) {
    final m = Float64List(16);
    for (var c = 0; c < 4; c++) {
      for (var r = 0; r < 4; r++) {
        var sum = 0.0;
        for (var k = 0; k < 4; k++) {
          sum += a[k * 4 + r] * b[c * 4 + k];
        }
        m[c * 4 + r] = sum;
      }
    }
    return m;
  }

  List<double> _transformPoint(Float64List m, double x, double y, double z) {
    final wx = m[0] * x + m[4] * y + m[8] * z + m[12];
    final wy = m[1] * x + m[5] * y + m[9] * z + m[13];
    final wz = m[2] * x + m[6] * y + m[10] * z + m[14];
    return [wx, wy, wz];
  }
}

/// Result of [GlbInspector.measure] — structural validity plus the measured
/// world-space extents in metres (X = width, Z = depth, Y = height).
class GlbMeasurement {
  const GlbMeasurement._({
    required this.ok,
    this.rejectionReason,
    this.width = 0,
    this.depth = 0,
    this.height = 0,
    this.minY = 0,
  });

  final bool ok;
  final String? rejectionReason;
  final double width;
  final double depth;
  final double height;
  final double minY;

  ({double width, double depth, double height}) get dimensionsM =>
      (width: width, depth: depth, height: height);

  /// `true` when the base sits within [kGlbFloorOffsetToleranceM] of y = 0 —
  /// the floor-centred authoring contract every tier consumes.
  bool get isFloorCentred => minY.abs() <= kGlbFloorOffsetToleranceM;
}

class _ParsedGlb {
  const _ParsedGlb._(this.gltf, this.rejection);
  const _ParsedGlb.ok(Map<String, dynamic> gltf) : this._(gltf, null);
  const _ParsedGlb.reject(String reason) : this._(null, reason);

  final Map<String, dynamic>? gltf;
  final String? rejection;
}

class _Aabb {
  double minX = double.infinity, minY = double.infinity, minZ = double.infinity;
  double maxX = -double.infinity,
      maxY = -double.infinity,
      maxZ = -double.infinity;

  void add(double x, double y, double z) {
    if (x < minX) minX = x;
    if (y < minY) minY = y;
    if (z < minZ) minZ = z;
    if (x > maxX) maxX = x;
    if (y > maxY) maxY = y;
    if (z > maxZ) maxZ = z;
  }
}
