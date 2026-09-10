import 'dart:io';
import 'dart:typed_data';

import 'package:twin_ar/features/admin/ar_media_management/services/vto_garment_file_picker.dart';

/// A fake picker returning a pre-seeded file (or `null` = admin cancelled), so
/// the ViewModel's pick→validate→stage path is testable with no platform
/// channel. Mirrors `FakeArModelFilePicker`.
class FakeVtoGarmentFilePicker implements VtoGarmentFilePicker {
  FakeVtoGarmentFilePicker([this.next]);

  File? next;
  Object? throwOnPick;
  int pickCount = 0;

  @override
  Future<File?> pickImage() async {
    pickCount++;
    if (throwOnPick != null) throw throwOnPick!;
    return next;
  }
}

/// Writes a **real, decodable** greyscale PNG of [width]×[height] to a temp
/// file. Uses an uncompressed (stored) zlib block so no deflate implementation
/// is needed — the bytes still parse and decode as a valid PNG.
File writePng(
  Directory dir,
  String name, {
  int width = 800,
  int height = 800,
  int fill = 0x7F,
}) {
  final bytes = buildPngBytes(width: width, height: height, fill: fill);
  return File('${dir.path}/$name')..writeAsBytesSync(bytes);
}

/// A minimal but structurally valid JPEG: SOI + APP0(JFIF) + a real SOF0 marker
/// carrying [width]/[height] + EOI. Enough for signature + header-dimension
/// validation (it is **not** a fully decodable scan — use [writePng] where the
/// test actually renders the image).
File writeJpegHeader(
  Directory dir,
  String name, {
  int width = 800,
  int height = 800,
}) {
  final bytes = buildJpegHeaderBytes(width: width, height: height);
  return File('${dir.path}/$name')..writeAsBytesSync(bytes);
}

/// Non-image junk with an image extension — for the "signature does not match"
/// path.
File writeFakeImage(Directory dir, String name) =>
    File('${dir.path}/$name')..writeAsBytesSync(List<int>.filled(512, 7));

// ── PNG (stored zlib block) ─────────────────────────────────────────────────

Uint8List buildPngBytes({
  required int width,
  required int height,
  int fill = 0x7F,
}) {
  final out = BytesBuilder();
  out.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);

  // IHDR
  final ihdr = BytesBuilder()
    ..add(_u32be(width))
    ..add(_u32be(height))
    ..add(const [8, 0, 0, 0, 0]); // bitdepth 8, colortype 0 (grey), rest 0
  out.add(_chunk('IHDR', ihdr.toBytes()));

  // Raw scanlines: each row = 1 filter byte (0) + `width` sample bytes.
  final raw = Uint8List(height * (1 + width));
  for (var y = 0; y < height; y++) {
    final rowStart = y * (1 + width);
    raw[rowStart] = 0;
    for (var x = 0; x < width; x++) {
      raw[rowStart + 1 + x] = fill;
    }
  }
  out.add(_chunk('IDAT', _zlibStored(raw)));
  out.add(_chunk('IEND', Uint8List(0)));
  return out.toBytes();
}

Uint8List _chunk(String type, Uint8List data) {
  final typeBytes = Uint8List.fromList(type.codeUnits);
  final body = BytesBuilder()
    ..add(typeBytes)
    ..add(data);
  final bodyBytes = body.toBytes();
  return Uint8List.fromList([
    ..._u32be(data.length),
    ...bodyBytes,
    ..._u32be(_crc32(bodyBytes)),
  ]);
}

Uint8List _zlibStored(Uint8List data) {
  final out = BytesBuilder()..add(const [0x78, 0x01]); // zlib header
  var offset = 0;
  while (offset < data.length || (data.isEmpty && offset == 0)) {
    final remaining = data.length - offset;
    final blockLen = remaining > 0xFFFF ? 0xFFFF : remaining;
    final isFinal = offset + blockLen >= data.length;
    out.addByte(isFinal ? 1 : 0);
    out.add([blockLen & 0xFF, (blockLen >> 8) & 0xFF]);
    final nlen = (~blockLen) & 0xFFFF;
    out.add([nlen & 0xFF, (nlen >> 8) & 0xFF]);
    out.add(data.sublist(offset, offset + blockLen));
    offset += blockLen;
    if (blockLen == 0) break;
  }
  out.add(_u32be(_adler32(data)));
  return out.toBytes();
}

// ── JPEG header ────────────────────────────────────────────────────────────

Uint8List buildJpegHeaderBytes({required int width, required int height}) {
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE0, 0x00, 0x10, // APP0, length 16
    0x4A, 0x46, 0x49, 0x46, 0x00, // "JFIF\0"
    0x01, 0x01, 0x00, 0x00, 0x01, 0x00, 0x01, 0x00, 0x00,
    0xFF, 0xC0, 0x00, 0x11, // SOF0, length 17
    0x08, // precision
    (height >> 8) & 0xFF, height & 0xFF,
    (width >> 8) & 0xFF, width & 0xFF,
    0x03, // components
    0x01, 0x22, 0x00,
    0x02, 0x11, 0x01,
    0x03, 0x11, 0x01,
    0xFF, 0xD9, // EOI
  ]);
}

// ── checksums ──────────────────────────────────────────────────────────────

List<int> _u32be(int v) => [
  (v >> 24) & 0xFF,
  (v >> 16) & 0xFF,
  (v >> 8) & 0xFF,
  v & 0xFF,
];

int _adler32(Uint8List data) {
  const mod = 65521;
  var a = 1, b = 0;
  for (final byte in data) {
    a = (a + byte) % mod;
    b = (b + a) % mod;
  }
  return ((b << 16) | a) & 0xFFFFFFFF;
}

final List<int> _crcTable = List<int>.generate(256, (n) {
  var c = n;
  for (var k = 0; k < 8; k++) {
    c = (c & 1) != 0 ? 0xEDB88320 ^ (c >> 1) : c >> 1;
  }
  return c;
});

int _crc32(Uint8List data) {
  var crc = 0xFFFFFFFF;
  for (final byte in data) {
    crc = _crcTable[(crc ^ byte) & 0xFF] ^ (crc >> 8);
  }
  return (crc ^ 0xFFFFFFFF) & 0xFFFFFFFF;
}
