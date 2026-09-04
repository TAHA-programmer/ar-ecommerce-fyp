import 'package:shared_preferences/shared_preferences.dart';

import '../models/marker_calibration.dart';

/// On-device persistence for the Marker-AR camera + printed-marker calibration
/// (`SCALE_CONTRACT.md` §3). Per-install, never mirrored to Firestore — it
/// describes the user's physical camera and their printed marker, not their
/// account.
///
/// Mirrors the project's other lightweight stores
/// (`OnboardingStore`, `RememberedLoginStore`).
class MarkerCalibrationStore {
  static const _markerMmKey = 'room_ar_marker_size_mm';
  static const _scaleTrimKey = 'room_ar_marker_scale_trim';
  static const _confirmedKey = 'room_ar_marker_calibration_confirmed';

  Future<MarkerCalibration> load() async {
    final prefs = await SharedPreferences.getInstance();
    return const MarkerCalibration().copyWith(
      markerSizeMm:
          prefs.getDouble(_markerMmKey) ?? MarkerCalibration.defaultMarkerMm,
      scaleTrim:
          prefs.getDouble(_scaleTrimKey) ?? MarkerCalibration.defaultScaleTrim,
      confirmed: prefs.getBool(_confirmedKey) ?? false,
    );
  }

  Future<void> save(MarkerCalibration calibration) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_markerMmKey, calibration.markerSizeMm);
    await prefs.setDouble(_scaleTrimKey, calibration.scaleTrim);
    await prefs.setBool(_confirmedKey, calibration.confirmed);
  }

  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_markerMmKey);
    await prefs.remove(_scaleTrimKey);
    await prefs.remove(_confirmedKey);
  }
}
