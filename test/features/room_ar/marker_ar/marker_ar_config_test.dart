import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_config.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';

void main() {
  group('MarkerArConfig.fromMap — native "config" mapping', () {
    test('decodes a full native payload', () {
      final c = MarkerArConfig.fromMap({
        'openCvOk': true,
        'openCvVersion': '4.12.0',
        'dict': 'DICT_5X5_100',
        'markerId': 0,
        'markerMm': 160.0,
        'chairDims': [0.70, 0.82, 0.72],
        'tableDims': [0.90, 0.42, 0.90],
        'lampDims': [0.20, 0.45, 0.20],
        'sofaDims': [2.65, 0.82, 1.65],
      });

      expect(c.openCvOk, isTrue);
      expect(c.openCvVersion, '4.12.0');
      expect(c.dict, 'DICT_5X5_100');
      expect(c.markerId, 0);
      expect(c.markerMm, 160.0);
    });

    test('exposes the exact canonical W/H/D metres for the four products', () {
      final c = MarkerArConfig.fromMap({
        'openCvOk': true,
        'chairDims': [0.70, 0.82, 0.72],
        'tableDims': [0.90, 0.42, 0.90],
        'lampDims': [0.20, 0.45, 0.20],
        'sofaDims': [2.65, 0.82, 1.65],
      });

      // [W(X), H(Y), D(Z)]
      expect(c.dimsFor(MarkerArObject.chair), [0.70, 0.82, 0.72]);
      expect(c.dimsFor(MarkerArObject.table), [0.90, 0.42, 0.90]);
      expect(c.dimsFor(MarkerArObject.lamp), [0.20, 0.45, 0.20]);
      expect(c.dimsFor(MarkerArObject.sofa), [2.65, 0.82, 1.65]);
    });

    test('covers exactly the four products — no QA cube', () {
      final c = MarkerArConfig.fromMap({'openCvOk': true});
      expect(c.dimensions.keys.toSet(), MarkerArObject.values.toSet());
      expect(MarkerArObject.values.length, 4);
      expect(
        MarkerArObject.values.map((o) => o.name),
        containsAll(['chair', 'table', 'lamp', 'sofa']),
      );
    });

    test('a stale native "cubeM" key is ignored, not surfaced', () {
      final c = MarkerArConfig.fromMap({'openCvOk': true, 'cubeM': 0.30});
      expect(c.dimensions.length, 4);
    });

    test('falls back to the built-in canonical dims when a key is missing', () {
      final c = MarkerArConfig.fromMap({'openCvOk': false});
      expect(c.dimsFor(MarkerArObject.chair), [0.70, 0.82, 0.72]);
      expect(c.dimsFor(MarkerArObject.sofa), [2.65, 0.82, 1.65]);
      expect(c.openCvOk, isFalse);
      expect(c.markerMm, 160.0);
    });

    test(
      'MarkerArConfig.fallback is coherent and marks the engine unavailable',
      () {
        const f = MarkerArConfig.fallback;
        expect(f.openCvOk, isFalse);
        expect(f.dimsFor(MarkerArObject.sofa), [2.65, 0.82, 1.65]);
        expect(f.markerMm, 160.0);
      },
    );
  });
}
