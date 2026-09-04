import 'marker_ar_object.dart';

/// Immutable device/engine configuration returned by the native `config` call.
///
/// The per-object real-world dimensions (`W(X) H(Y) D(Z)` metres) are the
/// authoritative values of the validated GLBs — the Flutter side never guesses
/// them (`SCALE_CONTRACT.md` §2). Defaults mirror the native constants so a
/// missing/failed channel still yields a coherent object.
class MarkerArConfig {
  final bool openCvOk;
  final String openCvVersion;
  final String dict;
  final int markerId;

  /// Factory default for the printed marker's outer black square (mm).
  final double markerMm;

  /// `[W(X), H(Y), D(Z)]` metres, per object.
  final Map<MarkerArObject, List<double>> dimensions;

  const MarkerArConfig({
    required this.openCvOk,
    required this.openCvVersion,
    required this.dict,
    required this.markerId,
    required this.markerMm,
    required this.dimensions,
  });

  /// The `[W, H, D]` metres for [object]; falls back to the built-in canonical
  /// values if the channel omitted it.
  List<double> dimsFor(MarkerArObject object) =>
      dimensions[object] ?? _fallback[object] ?? const [0.0, 0.0, 0.0];

  static const Map<MarkerArObject, List<double>> _fallback = {
    MarkerArObject.chair: [0.70, 0.82, 0.72],
    MarkerArObject.table: [0.90, 0.42, 0.90],
    MarkerArObject.lamp: [0.20, 0.45, 0.20],
    MarkerArObject.sofa: [2.65, 0.82, 1.65],
  };

  static const MarkerArConfig fallback = MarkerArConfig(
    openCvOk: false,
    openCvVersion: '?',
    dict: 'DICT_5X5_100',
    markerId: 0,
    markerMm: 160.0,
    dimensions: _fallback,
  );

  factory MarkerArConfig.fromMap(Map<dynamic, dynamic> m) {
    List<double> dl(dynamic v, List<double> orElse) => v is List
        ? v.map((e) => (e as num).toDouble()).toList(growable: false)
        : orElse;
    return MarkerArConfig(
      openCvOk: m['openCvOk'] == true,
      openCvVersion: (m['openCvVersion'] ?? '?').toString(),
      dict: (m['dict'] ?? 'DICT_5X5_100').toString(),
      markerId: (m['markerId'] as num?)?.toInt() ?? 0,
      markerMm: (m['markerMm'] as num?)?.toDouble() ?? 160.0,
      dimensions: {
        MarkerArObject.chair: dl(
          m['chairDims'],
          _fallback[MarkerArObject.chair]!,
        ),
        MarkerArObject.table: dl(
          m['tableDims'],
          _fallback[MarkerArObject.table]!,
        ),
        MarkerArObject.lamp: dl(m['lampDims'], _fallback[MarkerArObject.lamp]!),
        MarkerArObject.sofa: dl(m['sofaDims'], _fallback[MarkerArObject.sofa]!),
      },
    );
  }
}
