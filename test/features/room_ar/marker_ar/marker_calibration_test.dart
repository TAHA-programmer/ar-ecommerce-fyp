import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_calibration.dart';

void main() {
  group('MarkerCalibration', () {
    test('initial is uncalibrated at the factory defaults', () {
      const c = MarkerCalibration.initial;
      expect(c.markerSizeMm, 160.0);
      expect(c.scaleTrim, 1.0);
      expect(c.confirmed, isFalse);
      expect(c.isCalibrated, isFalse);
    });

    test('copyWith clamps marker mm and scale trim into range', () {
      const c = MarkerCalibration.initial;
      expect(
        c.copyWith(markerSizeMm: 5).markerSizeMm,
        MarkerCalibration.minMarkerMm,
      );
      expect(
        c.copyWith(markerSizeMm: 9999).markerSizeMm,
        MarkerCalibration.maxMarkerMm,
      );
      expect(
        c.copyWith(scaleTrim: 0.1).scaleTrim,
        MarkerCalibration.minScaleTrim,
      );
      expect(
        c.copyWith(scaleTrim: 9).scaleTrim,
        MarkerCalibration.maxScaleTrim,
      );
    });

    test('copyWith clamps non-finite values back to the default', () {
      const c = MarkerCalibration.initial;
      expect(c.copyWith(markerSizeMm: double.nan).markerSizeMm, 160.0);
      expect(c.copyWith(scaleTrim: double.infinity).scaleTrim, 1.0);
    });

    test('confirmed flips isCalibrated', () {
      final c = MarkerCalibration.initial.copyWith(confirmed: true);
      expect(c.isCalibrated, isTrue);
    });

    test('value equality', () {
      const a = MarkerCalibration(markerSizeMm: 162, scaleTrim: 1.02);
      const b = MarkerCalibration(markerSizeMm: 162, scaleTrim: 1.02);
      const d = MarkerCalibration(markerSizeMm: 162, scaleTrim: 1.03);
      expect(a, b);
      expect(a == d, isFalse);
    });

    test('trimIsNeutral helper', () {
      expect(trimIsNeutral(1.0), isTrue);
      expect(trimIsNeutral(1.0005), isTrue);
      expect(trimIsNeutral(1.05), isFalse);
    });
  });
}
