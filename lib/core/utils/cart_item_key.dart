import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Derives a deterministic, Firestore-document-ID-safe key for one cart line
/// from the canonical `(productId, selectedColor, selectedSize)` tuple
/// (Phase 8.10).
///
/// Correction from the original plan: the existing [CartItemModel.id]
/// getter (`'${productId}_${colorStr}_$sizeStr'`) is a fine LOCAL map key,
/// but it must never be used directly as a Firestore document ID.
/// `selectedColor`/`selectedSize` happen to be typed enums today (whose
/// `.name` is always alphanumeric), but a Firestore document ID must never
/// contain `/`, must not be exactly `.` or `..`, must not match
/// `__.*__`, and is capped at 1500 UTF-8 bytes - none of which the raw
/// composite string is provably safe against if a future caller ever
/// passes free-text color/size values, and a naive delimiter join is also
/// not collision-safe by construction (e.g. `('a_b', 'c', null)` and
/// `('a', 'b_c', null)` could produce the same joined string for a
/// different delimiter choice).
///
/// This function sidesteps both problems by hashing a length-prefixed,
/// unambiguous encoding of the tuple with SHA-256 and returning the hex
/// digest: fixed-length (64 lowercase hex characters), always a valid
/// Firestore document ID, deterministic across app restarts/devices (a
/// merge from two devices adding the same product+variant MUST resolve to
/// the same document), and safe for arbitrarily long or Unicode input since
/// the input is UTF-8 encoded before hashing, not interpolated into the
/// output.
///
/// A `null` component (no color/no size selected) is distinguished from any
/// real string value - including the empty string - by prefixing each
/// component with its own UTF-8 byte length before concatenating (a
/// "length-prefixed" encoding), so `(productId, null, 'x')` can never
/// collide with `(productId, 'null', 'x')` or similar edge cases a plain
/// delimiter join would be vulnerable to.
String cartItemFirestoreKey({
  required String productId,
  String? selectedColor,
  String? selectedSize,
}) {
  final buffer = BytesBuilder();
  for (final part in [productId, selectedColor, selectedSize]) {
    if (part == null) {
      // 0xFFFFFFFF-style sentinel length marker distinguishes "absent" from
      // any real (including zero-length) string, which is always encoded
      // with its true byte length below.
      buffer.add(_lengthPrefix(-1));
      continue;
    }
    final bytes = utf8.encode(part);
    buffer.add(_lengthPrefix(bytes.length));
    buffer.add(bytes);
  }
  return sha256.convert(buffer.toBytes()).toString();
}

/// 5-byte length prefix: 1 sentinel byte (0x00 = present, 0x01 = absent/
/// null) + 4 bytes big-endian length (ignored when the sentinel is
/// "absent"). Keeps the encoding trivially unambiguous without depending on
/// any delimiter character that could theoretically appear in input text.
List<int> _lengthPrefix(int length) {
  if (length < 0) {
    return [1, 0, 0, 0, 0];
  }
  return [
    0,
    (length >> 24) & 0xFF,
    (length >> 16) & 0xFF,
    (length >> 8) & 0xFF,
    length & 0xFF,
  ];
}
