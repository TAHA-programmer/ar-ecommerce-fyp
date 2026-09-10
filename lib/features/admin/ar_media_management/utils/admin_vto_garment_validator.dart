import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../../../../core/models/product/product_vto_metadata.dart';

/// The **authoring budget** an admin-uploaded Virtual Try-On garment image must
/// fit inside (Phase 9.3 Stage 3). Deliberately **stricter** than the transport
/// ceiling ([kVtoGarmentTransportMaxBytes] = 12 MiB, matched by `storage.rules`
/// and [VtoGarmentAsset.maxBytes]) — a stricter client cap is always safe, and a
/// garment reference photo never needs to be larger than this. Exact mirror of
/// Room-AR's `kArModelMaxUploadBytes`.
const int kVtoGarmentMaxUploadBytes = 8 * 1024 * 1024;

/// The absolute transport ceiling — matches `storage.rules`'
/// `products/{id}/vto/{assetFile}` `size < 12 MiB` and [VtoGarmentAsset.maxBytes].
/// Used only when *re-reading* bytes already in Storage (post-upload re-verify,
/// admin preview download), never for gating a new upload.
const int kVtoGarmentTransportMaxBytes = 12 * 1024 * 1024;

/// Only real raster photos the try-on provider and the [VtoGarmentAsset]
/// contract accept. `.webp`, `.gif`, `.heic`, `.tiff` and every other format are
/// rejected — the extension check is only a fast reject; the real decision is
/// the byte-level signature ([_sniffContentType]).
const Set<String> kVtoGarmentAllowedExtensions = {'jpg', 'jpeg', 'png'};

/// Below this longest-edge pixel size a garment image is genuinely unusable and
/// is **hard-rejected** (developer decision S7).
const int kVtoGarmentMinLongEdgePx = 256;

/// Thrown when a locally-picked garment image fails preflight, before any
/// Storage upload. Always carries clean, user-facing text (never a raw platform
/// exception) — mirrors [GlbValidationException] / `StorageServiceException`.
class GarmentValidationException implements Exception {
  final String message;
  const GarmentValidationException(this.message);

  @override
  String toString() => message;
}

/// The verified facts about a picked garment image the admin flow needs: its
/// exact byte size, lowercase-hex SHA-256, the content type derived from the
/// file **signature** (not the extension), and the pixel dimensions read from
/// the image header.
class AdminVtoGarmentInspection {
  const AdminVtoGarmentInspection({
    required this.sizeBytes,
    required this.sha256,
    required this.contentType,
    required this.width,
    required this.height,
  });

  final int sizeBytes;
  final String sha256;

  /// `image/jpeg` or `image/png`, decided from the magic bytes.
  final String contentType;

  final int width;
  final int height;

  double get sizeMib => sizeBytes / (1024 * 1024);

  int get longestEdgePx => width >= height ? width : height;

  /// `true` when the longest edge is under [VtoGarmentAsset.recommendedMinLongEdgePx]
  /// (768 px) — a **non-blocking** admin warning (developer decision S7).
  bool get isBelowRecommendedResolution =>
      longestEdgePx < VtoGarmentAsset.recommendedMinLongEdgePx;

  String get fileExtension => contentType == 'image/png' ? 'png' : 'jpg';
}

/// Preflights [file] as a production Virtual Try-On garment reference image and
/// returns the facts an admin needs to stage an upload.
///
/// Order (fails fast, cheapest first): existence → extension ∈ {jpg,jpeg,png} →
/// size in `(0, kVtoGarmentMaxUploadBytes]` → **real file signature** (PNG /
/// JPEG magic bytes, never the filename) → content-type derived from the
/// signature must agree with the extension → decode the header for
/// **width/height** (PNG IHDR / JPEG SOF; reject if undetermined or `< 256 px`
/// longest edge) → **SHA-256** of the exact bytes.
///
/// Never trusts the filename or an OS-reported MIME type. Uses synchronous
/// `dart:io` deliberately, matching `admin_glb_validator.dart` (the async
/// variants hang inside a `testWidgets` body).
Future<AdminVtoGarmentInspection> inspectVtoGarmentFile(File file) async {
  if (!file.existsSync()) {
    throw const GarmentValidationException(
      'The selected image could not be found. Please choose it again.',
    );
  }

  final path = file.path;
  final dotIndex = path.lastIndexOf('.');
  final extension = (dotIndex == -1 || dotIndex == path.length - 1)
      ? ''
      : path.substring(dotIndex + 1).toLowerCase();
  if (!kVtoGarmentAllowedExtensions.contains(extension)) {
    throw const GarmentValidationException(
      'Unsupported file type. Choose a JPEG or PNG image.',
    );
  }

  final length = file.lengthSync();
  if (length <= 0) {
    throw const GarmentValidationException('That file is empty.');
  }
  if (length > kVtoGarmentMaxUploadBytes) {
    final maxMb = (kVtoGarmentMaxUploadBytes / (1024 * 1024)).toStringAsFixed(
      0,
    );
    throw GarmentValidationException(
      'This image is ${(length / (1024 * 1024)).toStringAsFixed(1)} MB — over '
      'the $maxMb MB limit. Export it smaller (resize or re-compress).',
    );
  }

  final Uint8List bytes;
  try {
    bytes = file.readAsBytesSync();
  } catch (_) {
    throw const GarmentValidationException(
      'Could not read the selected file. Please choose it again.',
    );
  }

  final sniffed = _sniffContentType(bytes);
  if (sniffed == null) {
    throw const GarmentValidationException(
      'This file is not a valid JPEG or PNG image (its contents do not match '
      'either format).',
    );
  }

  // Signature ↔ extension parity — a `.png` that is really a JPEG (or vice
  // versa) is rejected, so the stored object, its `contentType` and its path
  // extension can never disagree (`VtoGarmentAsset` requires that agreement).
  final extIsPng = extension == 'png';
  final extIsJpg = extension == 'jpg' || extension == 'jpeg';
  if (sniffed == 'image/png' && !extIsPng) {
    throw const GarmentValidationException(
      'This file is really a PNG but its name does not end in .png. Rename it '
      'to .png, or export a real JPEG.',
    );
  }
  if (sniffed == 'image/jpeg' && !extIsJpg) {
    throw const GarmentValidationException(
      'This file is really a JPEG but its name ends ".png". Rename it to .jpg, '
      'or export a real PNG.',
    );
  }

  final dims = sniffed == 'image/png'
      ? _readPngDimensions(bytes)
      : _readJpegDimensions(bytes);
  if (dims == null) {
    throw const GarmentValidationException(
      'Could not read this image\'s dimensions. Re-export it from an image '
      'editor and try again.',
    );
  }
  final (width, height) = dims;
  if (width <= 0 || height <= 0) {
    throw const GarmentValidationException(
      'This image reports an invalid size. Re-export it and try again.',
    );
  }
  final longEdge = width >= height ? width : height;
  if (longEdge < kVtoGarmentMinLongEdgePx) {
    throw GarmentValidationException(
      'This image is only $width×$height px — too small to use. Provide at '
      'least $kVtoGarmentMinLongEdgePx px on the longest edge '
      '(${VtoGarmentAsset.recommendedMinLongEdgePx} px or more recommended).',
    );
  }

  final digest = sha256.convert(bytes).toString();

  return AdminVtoGarmentInspection(
    sizeBytes: length,
    sha256: digest,
    contentType: sniffed,
    width: width,
    height: height,
  );
}

/// `image/png` / `image/jpeg` from the leading bytes of [bytes], or `null` when
/// the buffer matches neither format's magic number. Used both here and by the
/// post-upload re-verify step (bytes already in Storage).
String? sniffVtoImageContentType(Uint8List bytes) => _sniffContentType(bytes);

/// The pixel `(width, height)` read from the image header for the given
/// [contentType] (`image/png` or `image/jpeg`), or `null` when it cannot be
/// determined. No image-decoding dependency — a direct PNG IHDR / JPEG SOF
/// header read.
(int, int)? readVtoImageDimensions(Uint8List bytes, String contentType) =>
    contentType == 'image/png'
    ? _readPngDimensions(bytes)
    : _readJpegDimensions(bytes);

// ── signature sniffing ──────────────────────────────────────────────────────

const List<int> _pngMagic = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A];

/// `image/png` / `image/jpeg` from the leading bytes, or `null` when neither.
String? _sniffContentType(Uint8List bytes) {
  if (bytes.length >= 8) {
    var isPng = true;
    for (var i = 0; i < 8; i++) {
      if (bytes[i] != _pngMagic[i]) {
        isPng = false;
        break;
      }
    }
    if (isPng) return 'image/png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'image/jpeg';
  }
  return null;
}

// ── header dimension readers (no image-decoding dependency) ──────────────────

/// PNG: the 8-byte magic is followed by the IHDR chunk — 4-byte length, the
/// ASCII tag `IHDR`, then width and height as big-endian uint32 at byte offsets
/// 16 and 20. Returns `null` when the buffer is too short or the tag is wrong.
(int, int)? _readPngDimensions(Uint8List b) {
  if (b.length < 24) return null;
  // bytes 12..15 must spell "IHDR"
  if (b[12] != 0x49 || b[13] != 0x48 || b[14] != 0x44 || b[15] != 0x52) {
    return null;
  }
  final width = _u32be(b, 16);
  final height = _u32be(b, 20);
  return (width, height);
}

/// JPEG: walk the marker segments from byte 2 until a Start-Of-Frame marker
/// (`0xC0`–`0xCF` except `0xC4` DHT / `0xC8` JPG / `0xCC` DAC), whose payload is
/// `precision(1) height(2) width(2)`. Standalone markers (`0xD0`–`0xD9`, `0x01`)
/// carry no length. Returns `null` when no SOF is found before the buffer ends.
(int, int)? _readJpegDimensions(Uint8List b) {
  var pos = 2; // skip SOI (FF D8)
  final len = b.length;
  while (pos + 3 < len) {
    if (b[pos] != 0xFF) {
      // Resync — skip fill bytes / entropy-coded noise.
      pos++;
      continue;
    }
    // Collapse any run of 0xFF padding before the marker id.
    var marker = b[pos + 1];
    var idPos = pos + 1;
    while (marker == 0xFF && idPos + 1 < len) {
      idPos++;
      marker = b[idPos];
    }
    final segStart = idPos + 1;

    if (marker == 0xD8 ||
        marker == 0x01 ||
        (marker >= 0xD0 && marker <= 0xD9)) {
      pos = segStart;
      continue;
    }
    if (marker == 0xD9) return null; // EOI
    if (segStart + 1 >= len) return null;
    final segLen = _u16be(b, segStart);
    if (segLen < 2) return null;

    final isSof =
        marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isSof) {
      // payload: [precision(1)][height(2)][width(2)]
      if (segStart + 7 > len) return null;
      final height = _u16be(b, segStart + 3);
      final width = _u16be(b, segStart + 5);
      return (width, height);
    }
    if (marker == 0xDA) return null; // start of scan — no SOF seen
    pos = segStart + segLen;
  }
  return null;
}

int _u16be(Uint8List b, int i) => (b[i] << 8) | b[i + 1];

int _u32be(Uint8List b, int i) =>
    (b[i] << 24) | (b[i + 1] << 16) | (b[i + 2] << 8) | b[i + 3];
