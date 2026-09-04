import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/admin/ar_media_management/utils/admin_glb_validator.dart';
import 'package:twin_ar/features/room_ar/model_delivery/glb_inspector.dart';

import '../../room_ar/model_delivery/glb_test_support.dart';
import 'ar_glb_test_support.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('glb_validator_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'a valid floor-centred GLB returns measured dims + a 64-hex sha',
    () async {
      final file = writeBoxGlb(
        dir: tmp,
        name: 'ok.glb',
        x: 1.2,
        y: 0.5,
        z: 0.9,
      );
      final result = await inspectArGlbFile(file);
      expect(result.measuredM.width, closeTo(1.2, 0.01));
      expect(result.measuredM.height, closeTo(0.5, 0.01));
      expect(result.measuredM.depth, closeTo(0.9, 0.01));
      expect(result.floorCentred, isTrue);
      expect(result.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
      expect(result.sizeBytes, file.lengthSync());
    },
  );

  test('the sha is deterministic for identical bytes', () async {
    final a = writeBoxGlb(dir: tmp, name: 'a.glb');
    final b = writeBoxGlb(dir: tmp, name: 'b.glb');
    expect(
      (await inspectArGlbFile(a)).sha256,
      (await inspectArGlbFile(b)).sha256,
    );
  });

  test('a non-glb file is rejected', () async {
    final junk = writeJunkFile(tmp, 'junk.glb');
    expect(
      () => inspectArGlbFile(junk),
      throwsA(isA<GlbValidationException>()),
    );
  });

  test('a non-.glb extension is rejected before reading bytes', () async {
    final f = writeBoxGlb(dir: tmp, name: 'model.gltf');
    expect(
      () => inspectArGlbFile(f),
      throwsA(
        isA<GlbValidationException>().having(
          (e) => e.message,
          'message',
          contains('.glb'),
        ),
      ),
    );
  });

  test('a model that is not floor-centred is rejected', () async {
    final f = writeBoxGlb(dir: tmp, name: 'floating.glb', minY: 0.4);
    expect(
      () => inspectArGlbFile(f),
      throwsA(
        isA<GlbValidationException>().having(
          (e) => e.message,
          'message',
          contains('floor-centred'),
        ),
      ),
    );
  });

  test('dimensions that do not match the geometry are rejected', () async {
    final f = writeBoxGlb(dir: tmp, name: 'box.glb', x: 1.0, y: 1.0, z: 1.0);
    expect(
      () => inspectArGlbFile(
        f,
        expected: const GlbExpectedBox(widthM: 2.0, depthM: 1.0, heightM: 1.0),
      ),
      throwsA(isA<GlbValidationException>()),
    );
    // matching dims pass
    final ok = await inspectArGlbFile(
      f,
      expected: const GlbExpectedBox(widthM: 1.0, depthM: 1.0, heightM: 1.0),
    );
    expect(ok.sha256, isNotEmpty);
  });

  test('an empty file is rejected', () async {
    final f = File('${tmp.path}/empty.glb')..writeAsBytesSync(const []);
    expect(() => inspectArGlbFile(f), throwsA(isA<GlbValidationException>()));
  });

  test('the upload cap is the 8 MiB authoring budget, distinct from the '
      '12 MiB transport ceiling', () {
    expect(kArModelMaxUploadBytes, 8 * 1024 * 1024);
    expect(kArModelTransportMaxBytes, 12 * 1024 * 1024);
    expect(kArModelMaxUploadBytes, lessThan(kArModelTransportMaxBytes));
  });

  test('a GLB over the 8 MiB authoring budget is rejected even though it is '
      'under the transport ceiling', () async {
    // A structurally valid GLB padded to ~8.5 MiB via a big BIN chunk.
    final big = Uint8List(9 * 1024 * 1024);
    final bytes = buildGlb(boxGltf(x: 0.7, y: 0.8, z: 0.7), bin: big);
    final f = File('${tmp.path}/heavy.glb')..writeAsBytesSync(bytes);
    expect(f.lengthSync(), greaterThan(kArModelMaxUploadBytes));
    expect(f.lengthSync(), lessThan(kArModelTransportMaxBytes));
    expect(
      () => inspectArGlbFile(f),
      throwsA(
        isA<GlbValidationException>().having(
          (e) => e.message,
          'message',
          contains('authoring budget'),
        ),
      ),
    );
  });
}
