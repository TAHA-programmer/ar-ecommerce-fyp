import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_calibration.dart';
import 'package:twin_ar/features/room_ar/marker_ar/services/marker_calibration_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('load returns the uncalibrated defaults on a fresh install', () async {
    final loaded = await MarkerCalibrationStore().load();
    expect(loaded, MarkerCalibration.initial);
    expect(loaded.isCalibrated, isFalse);
  });

  test('save then load round-trips the calibration', () async {
    final store = MarkerCalibrationStore();
    const cal = MarkerCalibration(
      markerSizeMm: 158.5,
      scaleTrim: 1.04,
      confirmed: true,
    );
    await store.save(cal);

    final reloaded = await MarkerCalibrationStore().load();
    expect(reloaded.markerSizeMm, 158.5);
    expect(reloaded.scaleTrim, 1.04);
    expect(reloaded.confirmed, isTrue);
  });

  test(
    'persisted value survives across store instances (per-install)',
    () async {
      await MarkerCalibrationStore().save(
        const MarkerCalibration(markerSizeMm: 200, confirmed: true),
      );
      SharedPreferences.setMockInitialValues({
        'room_ar_marker_size_mm': 200.0,
        'room_ar_marker_scale_trim': 1.0,
        'room_ar_marker_calibration_confirmed': true,
      });
      final again = await MarkerCalibrationStore().load();
      expect(again.markerSizeMm, 200);
      expect(again.confirmed, isTrue);
    },
  );

  test('clear resets to the uncalibrated defaults', () async {
    final store = MarkerCalibrationStore();
    await store.save(
      const MarkerCalibration(markerSizeMm: 175, confirmed: true),
    );
    await store.clear();
    expect(await store.load(), MarkerCalibration.initial);
  });
}
