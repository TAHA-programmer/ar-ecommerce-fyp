import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/room_ar/model_delivery/glb_inspector.dart';

import 'glb_test_support.dart';

void main() {
  const inspector = GlbInspector();
  final chairBox = const GlbExpectedBox(
    widthM: 0.70,
    depthM: 0.72,
    heightM: 0.82,
  );

  test('accepts a well-formed, correctly-sized, floor-centred glb', () {
    final bytes = buildGlb(
      boxGltf(x: 0.70, y: 0.82, z: 0.72),
      bin: Uint8List(8),
    );
    final r = inspector.inspect(bytes, expected: chairBox);
    expect(r.ok, isTrue);
    expect(r.width, closeTo(0.70, 1e-9));
    expect(r.depth, closeTo(0.72, 1e-9));
    expect(r.height, closeTo(0.82, 1e-9));
  });

  test('rejects bad magic bytes', () {
    final bytes = Uint8List.fromList(
      List<int>.filled(64, 0)..setRange(0, 4, [1, 2, 3, 4]),
    );
    expect(inspector.inspect(bytes).ok, isFalse);
    expect(inspector.inspect(bytes).rejectionReason, contains('magic'));
  });

  test('rejects a truncated file (declared length != actual)', () {
    final full = buildGlb(boxGltf(x: 0.7, y: 0.82, z: 0.72));
    final truncated = Uint8List.sublistView(full, 0, full.length - 12);
    final r = inspector.inspect(truncated);
    expect(r.ok, isFalse);
    expect(r.rejectionReason, contains('length'));
  });

  test('rejects trailing bytes after the last chunk', () {
    final full = buildGlb(boxGltf(x: 0.7, y: 0.82, z: 0.72));
    final padded = Uint8List(full.length + 4)..setRange(0, full.length, full);
    // fix the declared length back so only "trailing bytes" trips
    final bd = ByteData.sublistView(padded);
    bd.setUint32(8, full.length, Endian.little);
    final r = inspector.inspect(padded);
    expect(r.ok, isFalse);
  });

  test('rejects an external buffer reference', () {
    final g = boxGltf(x: 0.7, y: 0.82, z: 0.72);
    g['buffers'] = [
      {'uri': 'model.bin', 'byteLength': 8},
    ];
    final r = inspector.inspect(buildGlb(g));
    expect(r.ok, isFalse);
    expect(r.rejectionReason, contains('external buffer'));
  });

  test('rejects a bounding box outside the ±3% tolerance', () {
    final bytes = buildGlb(boxGltf(x: 1.0, y: 1.0, z: 1.0));
    final r = inspector.inspect(bytes, expected: chairBox);
    expect(r.ok, isFalse);
    expect(r.rejectionReason, contains('bounding box'));
  });

  test('accepts a box within tolerance (2% off)', () {
    final bytes = buildGlb(boxGltf(x: 0.70 * 1.02, y: 0.82, z: 0.72));
    expect(inspector.inspect(bytes, expected: chairBox).ok, isTrue);
  });

  test('rejects a model that is not floor-centred', () {
    final bytes = buildGlb(boxGltf(x: 0.70, y: 0.82, z: 0.72, minY: -0.41));
    final r = inspector.inspect(bytes, expected: chairBox);
    expect(r.ok, isFalse);
    expect(r.rejectionReason, contains('floor'));
  });

  test('applies a node scale transform when measuring the box', () {
    // author a 0.35 m box, scale it ×2 on the node → 0.70 m world
    final g = boxGltf(
      x: 0.35,
      y: 0.41,
      z: 0.36,
      nodeExtra: {
        'scale': [2.0, 2.0, 2.0],
      },
    );
    final r = inspector.inspect(buildGlb(g), expected: chairBox);
    expect(r.ok, isTrue);
    expect(r.width, closeTo(0.70, 1e-9));
  });

  test('rejects when a POSITION accessor has no min/max to measure', () {
    final g = boxGltf(x: 0.7, y: 0.82, z: 0.72);
    (g['accessors'] as List)[0] = {'type': 'VEC3', 'componentType': 5126};
    final r = inspector.inspect(buildGlb(g), expected: chairBox);
    expect(r.ok, isFalse);
    expect(r.rejectionReason, contains('bounding box'));
  });

  test('enforces maxBytes before parsing', () {
    final bytes = buildGlb(boxGltf(x: 0.7, y: 0.82, z: 0.72));
    final r = inspector.inspect(bytes, maxBytes: 8);
    expect(r.ok, isFalse);
    expect(r.rejectionReason, contains('size'));
  });
}
