import 'package:flutter/services.dart';

/// Load state of the Tier-3 preview renderer, straight from the native
/// `twin_ar/room_ar/preview/events` stream.
enum RoomArPreviewLoad { loading, ready, failed }

/// Thin Dart ↔ platform boundary for the Tier-3 Interactive 3D Preview
/// ([RoomArPreviewPlugin]). No logic — it marshals calls and decodes the load
/// stream. All orbit / pan / zoom decisions live in [RoomArPreviewViewModel].
class RoomArPreviewChannel {
  static const String viewType = 'twin_ar/room_ar/preview/view';
  static const String _methodsName = 'twin_ar/room_ar/preview/methods';
  static const String _eventsName = 'twin_ar/room_ar/preview/events';

  RoomArPreviewChannel({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel(_methodsName),
      _events = events ?? const EventChannel(_eventsName);

  final MethodChannel _methods;
  final EventChannel _events;

  Stream<RoomArPreviewLoad> loadStates() =>
      _events.receiveBroadcastStream().map((e) {
        final s = (e as Map)['state'] as String?;
        return switch (s) {
          'ready' => RoomArPreviewLoad.ready,
          'failed' => RoomArPreviewLoad.failed,
          _ => RoomArPreviewLoad.loading,
        };
      });

  /// [mode] is the native renderer key: `chair`/`table`/`lamp`/`sofa` for the
  /// four bundled products, or any other non-blank key (e.g. `admin`) for a
  /// caller that only ever supplies a [verifiedPath].
  Future<void> setModel(String mode, String? verifiedPath) =>
      _invoke('setModel', {'mode': mode, 'path': verifiedPath});

  Future<void> orbit(double dx, double dy) =>
      _invoke('orbit', {'dx': dx, 'dy': dy});

  Future<void> pan(double dx, double dy) =>
      _invoke('pan', {'dx': dx, 'dy': dy});

  Future<void> zoom(double scale) => _invoke('zoom', {'scale': scale});

  Future<void> resetView() => _invoke('reset');

  Future<void> setActive(bool active) =>
      _invoke('setActive', {'active': active});

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) =>
      _methods.invokeMethod(method, args).catchError((_) {});
}
