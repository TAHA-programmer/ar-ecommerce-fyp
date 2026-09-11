import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Thrown when a picked/captured photo fails validation — always carries an
/// already customer-safe [message] to show directly (never a raw decode
/// error).
class PersonPhotoValidationException implements Exception {
  final String message;
  const PersonPhotoValidationException(this.message);

  @override
  String toString() => 'PersonPhotoValidationException($message)';
}

/// Deterministically validates + re-encodes a customer's Virtual Try-On
/// person photo to JPEG (Phase 9.3 Stage 5).
///
/// `storage.rules` accepts the upload object ONLY at a literal `{sha}.jpg`
/// path (`functions/src/lib/tryOn/session.ts` — "the documented client
/// design downscales/re-encodes every picked photo to JPEG before upload").
/// Rather than trust `image_picker`'s own (platform-version-dependent,
/// undocumented-guarantee) recompression behaviour, this always decodes the
/// picked bytes and re-encodes them itself — deterministic, testable, and
/// correct regardless of whether the source was a PNG, a HEIC-converted JPEG,
/// or an already-JPEG camera capture.
class PersonPhotoProcessor {
  const PersonPhotoProcessor._();

  /// Hard ceiling on the *source* file before even attempting to decode it —
  /// well above [maxUploadBytes] since the source is re-compressed, but
  /// guards against decoding an absurdly large file into memory.
  static const int maxSourceBytes = 30 * 1024 * 1024;

  /// Mirrors the server's `VTO_PERSON_PHOTO_MAX_BYTES`
  /// (`functions/src/config.ts`) — re-verified server-side regardless, but a
  /// client-side check avoids a wasted upload + guaranteed server rejection.
  static const int maxUploadBytes = 12 * 1024 * 1024;

  /// A photo whose longest edge is below this is very unlikely to produce a
  /// usable try-on preview (a thumbnail, an icon, a corrupted partial
  /// decode) — rejected with a clear, actionable message rather than spent
  /// on a paid generation call that would likely fail anyway.
  static const int minLongEdgePx = 200;

  /// Downscale target — matches `DeviceImagePickerService`'s product-image
  /// sizing; ample resolution for a full-body photo without inflating the
  /// upload.
  static const int targetLongEdgePx = 1600;

  static const int _initialJpegQuality = 85;
  static const int _fallbackJpegQuality = 70;

  /// Decodes [sourceBytes], validates it, downsizes if needed, and re-encodes
  /// to JPEG. Always returns JPEG bytes ready to upload as `{sessionId}.jpg`
  /// with `contentType: image/jpeg` — regardless of the source format.
  ///
  /// Throws [PersonPhotoValidationException] with a customer-ready message
  /// for: an empty/oversized source, bytes that don't decode as an image, an
  /// implausibly small image, or a result that still exceeds
  /// [maxUploadBytes] even at reduced quality.
  static Uint8List processToJpeg(Uint8List sourceBytes) {
    if (sourceBytes.isEmpty) {
      throw const PersonPhotoValidationException(
        "That photo couldn't be read. Please choose or take another.",
      );
    }
    if (sourceBytes.length > maxSourceBytes) {
      throw const PersonPhotoValidationException(
        'That photo is too large. Please choose a smaller photo.',
      );
    }

    final decoded = img.decodeImage(sourceBytes);
    if (decoded == null) {
      throw const PersonPhotoValidationException(
        "That file couldn't be used as a photo. Please choose or take another.",
      );
    }

    final longEdge = decoded.width > decoded.height
        ? decoded.width
        : decoded.height;
    if (longEdge < minLongEdgePx) {
      throw const PersonPhotoValidationException(
        'That photo is too small. Please choose a clearer, higher-resolution photo.',
      );
    }

    final img.Image resized = longEdge > targetLongEdgePx
        ? (decoded.width >= decoded.height
              ? img.copyResize(decoded, width: targetLongEdgePx)
              : img.copyResize(decoded, height: targetLongEdgePx))
        : decoded;

    final jpegBytes = Uint8List.fromList(
      img.encodeJpg(resized, quality: _initialJpegQuality),
    );
    if (jpegBytes.length <= maxUploadBytes) {
      return jpegBytes;
    }

    // Rare (a very large/high-detail photo even after downscaling) — retry
    // once at a lower quality before giving up.
    final smallerJpegBytes = Uint8List.fromList(
      img.encodeJpg(resized, quality: _fallbackJpegQuality),
    );
    if (smallerJpegBytes.length <= maxUploadBytes) {
      return smallerJpegBytes;
    }

    throw const PersonPhotoValidationException(
      'That photo is too large. Please choose a smaller photo.',
    );
  }
}
