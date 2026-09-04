import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../room_ar/model_delivery/glb_inspector.dart';

/// The **authoring budget** an admin-uploaded Room-AR GLB must fit inside —
/// `_ar_assets/SCALE_CONTRACT.md` §2 (≤ 8 MB, ideally ≤ 3 MB; the four
/// approved products are ≈ 1–1.5 MB). The admin upload path enforces this so
/// published models stay lean.
///
/// This is deliberately **stricter** than the transport ceiling
/// ([kArModelTransportMaxBytes] = 12 MiB) enforced by `storage.rules` and
/// `RoomArModelService.defaultMaxDownloadBytes` — those keep a safety margin
/// above the authoring budget; a stricter client cap is always safe. Anything
/// that passes here comfortably clears both.
const int kArModelMaxUploadBytes = 8 * 1024 * 1024;

/// The absolute transport ceiling — matches `storage.rules`'
/// `products/{id}/ar/{modelFile}` `size <= 12 MB` and
/// `RoomArModelService.defaultMaxDownloadBytes`. Used only when *re-reading*
/// bytes already in Storage (post-upload re-verify, admin preview download),
/// never for gating a new upload.
const int kArModelTransportMaxBytes = 12 * 1024 * 1024;

/// Only a real glTF-binary container. `.gltf` (multi-file), `.usdz`, `.obj`
/// and every other format the legacy mock surface *claimed* to accept are
/// rejected — the production runtime (Filament + `GlbInspector`) is `.glb`
/// only (`ProductArMetadata.glbFormat`).
const Set<String> kArModelAllowedExtensions = {'glb'};

/// Thrown when a locally-picked GLB fails preflight, before any Storage
/// upload. Always carries clean, user-facing text (never a raw platform
/// exception) — mirrors [ImageValidationException] /
/// `StorageServiceException`.
class GlbValidationException implements Exception {
  final String message;
  const GlbValidationException(this.message);

  @override
  String toString() => message;
}

/// The verified facts about a picked GLB the admin flow needs: its exact
/// byte size, lowercase-hex SHA-256, the world-space bounding box measured
/// from the mesh data, and whether it sits on the floor (`min-Y ≈ 0`).
class AdminGlbInspection {
  const AdminGlbInspection({
    required this.sizeBytes,
    required this.sha256,
    required this.measuredM,
    required this.floorCentred,
  });

  final int sizeBytes;
  final String sha256;
  final ({double width, double depth, double height}) measuredM;
  final bool floorCentred;

  double get sizeMib => sizeBytes / (1024 * 1024);
}

/// Preflights [file] as a production Room-AR GLB and returns the facts an
/// admin needs to capture/confirm dimensions and stage an upload.
///
/// Order (fails fast, cheapest first): existence → extension → size →
/// structural GLB parse (`GlbInspector` re-derives everything from the bytes:
/// magic, container version, chunk table, self-contained, glTF 2.0) →
/// bounding-box measurement → SHA-256. When [expected] is supplied the
/// measured box must also match it within `GlbInspector`'s ±3 % / ±2 cm
/// tolerance — this is the "does the file match the dimensions the admin
/// entered" gate.
///
/// Never trusts the filename or a MIME type: the extension check is only a
/// fast reject, the real decision is the byte-level parse.
///
/// Uses the synchronous `dart:io` APIs deliberately — see
/// `image_upload_validator.dart`'s note on why the async variants hang inside
/// a `testWidgets` body.
Future<AdminGlbInspection> inspectArGlbFile(
  File file, {
  GlbExpectedBox? expected,
  GlbInspector inspector = const GlbInspector(),
}) async {
  if (!file.existsSync()) {
    throw const GlbValidationException(
      'The selected 3D model could not be found. Please choose it again.',
    );
  }

  final path = file.path;
  final dotIndex = path.lastIndexOf('.');
  final extension = (dotIndex == -1 || dotIndex == path.length - 1)
      ? ''
      : path.substring(dotIndex + 1).toLowerCase();
  if (!kArModelAllowedExtensions.contains(extension)) {
    throw const GlbValidationException(
      'Unsupported file type. Choose a binary glTF (.glb) model.',
    );
  }

  final length = file.lengthSync();
  if (length <= 0) {
    throw const GlbValidationException('That file is empty.');
  }
  if (length > kArModelMaxUploadBytes) {
    final maxMb = (kArModelMaxUploadBytes / (1024 * 1024)).toStringAsFixed(0);
    throw GlbValidationException(
      'This model is ${(length / (1024 * 1024)).toStringAsFixed(1)} MB — over '
      'the $maxMb MB authoring budget. Re-export it lighter (decimate mesh / '
      'shrink textures).',
    );
  }

  final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } catch (_) {
    throw const GlbValidationException(
      'Could not read the selected file. Please choose it again.',
    );
  }

  final measurement = inspector.measure(
    bytes,
    maxBytes: kArModelMaxUploadBytes,
  );
  if (!measurement.ok) {
    throw GlbValidationException(_friendlyReason(measurement.rejectionReason));
  }
  if (!measurement.isFloorCentred) {
    throw GlbValidationException(_friendlyReason('model is not floor-centred'));
  }

  if (expected != null) {
    final match = inspector.inspect(
      bytes,
      expected: expected,
      maxBytes: kArModelMaxUploadBytes,
    );
    if (!match.ok) {
      throw GlbValidationException(_friendlyReason(match.rejectionReason));
    }
  }

  final digest = sha256.convert(bytes).toString();

  return AdminGlbInspection(
    sizeBytes: length,
    sha256: digest,
    measuredM: measurement.dimensionsM,
    floorCentred: measurement.isFloorCentred,
  );
}

/// Maps [GlbInspector]'s terse machine slugs to a sentence an admin can act
/// on. Anything unrecognised passes through unchanged (the slugs are already
/// short and readable).
String _friendlyReason(String? reason) {
  switch (reason) {
    case 'file exceeds maximum size':
      return 'This model is too large to upload.';
    case 'not a glb (bad magic bytes)':
    case 'file too small to be a glb':
    case 'unsupported glb container version':
    case 'glTF JSON does not parse':
    case 'glTF JSON is not an object':
    case 'glTF asset version is not 2.0':
      return 'This file is not a valid binary glTF (.glb) model.';
    case 'declared length does not match file (truncated or padded)':
    case 'chunk overruns the file':
    case 'trailing bytes after last chunk':
    case 'duplicate JSON chunk':
    case 'no JSON chunk':
      return 'This .glb file looks corrupt or incomplete.';
    case 'references an external buffer':
    case 'buffer declared but no BIN chunk':
      return 'This model references external files. Export it as a single '
          'self-contained .glb.';
    case 'cannot measure bounding box':
      return 'This model has no measurable geometry.';
    case 'bounding box does not match declared dimensions':
      return 'The model\'s real size does not match the width / depth / '
          'height you entered.';
    case 'model is not floor-centred':
      return 'This model is not floor-centred (its base must sit at height 0).';
    default:
      return reason == null
          ? 'This 3D model could not be validated.'
          : 'This 3D model could not be validated: $reason.';
  }
}
