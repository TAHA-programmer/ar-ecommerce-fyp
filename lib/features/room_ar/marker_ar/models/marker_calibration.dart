/// Camera + printed-marker calibration (`SCALE_CONTRACT.md` §3).
///
/// Camera-and-marker specific, not product specific — set once per install:
///  * [markerSizeMm] — the physically-measured outer black-square side length.
///    solvePnP's object points become `±markerSizeMm/2000` m, so the pose is
///    metric when this matches the print.
///  * [scaleTrim] — a residual visual-scale correction (absorbs the
///    camera-intrinsic approximation), applied as the model `scaleMultiplier`.
///  * [confirmed] — the user has actually measured the marker. Until then the
///    UI shows an honest "sizes approximate ±10%" banner.
class MarkerCalibration {
  static const double defaultMarkerMm = 160.0;
  static const double defaultScaleTrim = 1.0;

  static const double minMarkerMm = 40.0;
  static const double maxMarkerMm = 400.0;
  static const double minScaleTrim = 0.5;
  static const double maxScaleTrim = 2.0;

  final double markerSizeMm;
  final double scaleTrim;
  final bool confirmed;

  const MarkerCalibration({
    this.markerSizeMm = defaultMarkerMm,
    this.scaleTrim = defaultScaleTrim,
    this.confirmed = false,
  });

  static const MarkerCalibration initial = MarkerCalibration();

  bool get isCalibrated => confirmed;

  MarkerCalibration copyWith({
    double? markerSizeMm,
    double? scaleTrim,
    bool? confirmed,
  }) => MarkerCalibration(
    markerSizeMm: _clampMarkerMm(markerSizeMm ?? this.markerSizeMm),
    scaleTrim: _clampTrim(scaleTrim ?? this.scaleTrim),
    confirmed: confirmed ?? this.confirmed,
  );

  static double _clampMarkerMm(double v) =>
      v.isFinite ? v.clamp(minMarkerMm, maxMarkerMm) : defaultMarkerMm;

  static double _clampTrim(double v) =>
      v.isFinite ? v.clamp(minScaleTrim, maxScaleTrim) : defaultScaleTrim;

  @override
  bool operator ==(Object other) =>
      other is MarkerCalibration &&
      (other.markerSizeMm - markerSizeMm).abs() < 1e-6 &&
      (other.scaleTrim - scaleTrim).abs() < 1e-6 &&
      other.confirmed == confirmed;

  @override
  int get hashCode => Object.hash(
    (markerSizeMm * 1000).round(),
    (scaleTrim * 1000).round(),
    confirmed,
  );
}

/// Trim `≈ 1.0` within [tol]? (helper for tests / UI).
bool trimIsNeutral(double trim, {double tol = 1e-3}) =>
    (trim - 1.0).abs() < tol;
