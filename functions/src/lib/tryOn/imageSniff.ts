/**
 * Pure magic-number image sniffing (Phase 9.3 Stage 4 hardening).
 *
 * Storage rules can only assert the *declared* `contentType` metadata on a
 * write, never the actual bytes ("Rules cannot hash the payload" - the same
 * limitation already documented on `hasArModelProvenance()` /
 * `hasVtoGarmentProvenance()` in `storage.rules`). Every image this backend
 * forwards to a paid third-party provider, or hands back to a customer, is
 * therefore re-verified here against its real byte signature before it is
 * trusted - mirroring the Dart Admin pipeline's own
 * `admin_vto_garment_validator.dart` PNG/JPEG magic-byte check.
 */

export type SniffedImageType = "image/jpeg" | "image/png";

const JPEG_MAGIC = [0xff, 0xd8, 0xff];
const PNG_MAGIC = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];

function startsWith(bytes: Buffer, signature: number[]): boolean {
  if (bytes.length < signature.length) return false;
  for (let i = 0; i < signature.length; i++) {
    if (bytes[i] !== signature[i]) return false;
  }
  return true;
}

/** `null` when the bytes match neither supported signature. */
export function sniffImageContentType(bytes: Buffer): SniffedImageType | null {
  if (startsWith(bytes, PNG_MAGIC)) return "image/png";
  // JPEG signature check first 3 bytes only (FF D8 FF) - covers every JFIF/EXIF variant.
  if (startsWith(bytes, JPEG_MAGIC)) return "image/jpeg";
  return null;
}

/** `true` only when the bytes' real signature matches the declared/claimed content type exactly. */
export function bytesMatchDeclaredType(bytes: Buffer, declaredContentType: string): boolean {
  return sniffImageContentType(bytes) === declaredContentType;
}

export function extensionForContentType(contentType: string): "jpg" | "png" | null {
  if (contentType === "image/png") return "png";
  if (contentType === "image/jpeg") return "jpg";
  return null;
}
