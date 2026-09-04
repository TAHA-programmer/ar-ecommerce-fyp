import 'dart:async';

import 'package:flutter/services.dart';

import '../models/marker_ar_config.dart';
import '../models/marker_ar_frame.dart';
import '../models/marker_ar_object.dart';

/// Thin Dart ↔ platform boundary for the Tier-2 Marker-AR native engine
/// (`RoomArMarkerPlugin.kt`). **No business logic** — it only marshals calls and
/// decodes the event stream into typed models. The `MarkerArViewModel` owns all
/// observable state and every decision.
///
/// Channel names and the neutral wire protocol are the production contract;
/// the native math behind them is the physically-approved PoC engine unchanged.
class RoomArMarkerChannel {
  static const String _methodsName = 'twin_ar/room_ar/marker/methods';
  static const String _eventsName = 'twin_ar/room_ar/marker/events';

  /// The PlatformView type string for `AndroidView(viewType: ...)`.
  static const String viewType = 'twin_ar/room_ar/marker/view';

  final MethodChannel _methods;
  final EventChannel _events;

  RoomArMarkerChannel({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel(_methodsName),
      _events = events ?? const EventChannel(_eventsName);

  /// One-shot device/engine configuration (OpenCV availability, marker contract,
  /// canonical per-object dimensions). Falls back to sane defaults on any error
  /// so the screen can still show an honest "AR unavailable" state.
  Future<MarkerArConfig> config() async {
    try {
      final m = await _methods.invokeMethod<Map<dynamic, dynamic>>('config');
      if (m == null) return MarkerArConfig.fallback;
      return MarkerArConfig.fromMap(m);
    } catch (_) {
      return MarkerArConfig.fallback;
    }
  }

  /// The broadcast stream of per-frame detector output.
  Stream<MarkerArFrame> frames() => _events.receiveBroadcastStream().map(
    (e) => MarkerArFrame.fromMap(e as Map<dynamic, dynamic>),
  );

  /// Generate the raw ArUco marker PNG (used to build the printable A4 sheet).
  Future<Uint8List> markerPng({int px = 1400}) async {
    final b = await _methods.invokeMethod<Uint8List>('generateMarkerPng', {
      'px': px,
    });
    return b ?? Uint8List(0);
  }

  Future<void> setObject(MarkerArObject object) =>
      _invoke('setArMode', {'mode': object.mode});

  /// Phase 9.2 R10 — hand the native renderer a **verified** external GLB
  /// ([absolutePath], from `RoomArModelService`) for [object], or pass null to
  /// drop the override and fall back to the bundled asset. Only a path that has
  /// already passed magic-byte / length / structure / SHA-256 / bounding-box
  /// verification may be passed here.
  Future<void> setExternalModel(MarkerArObject object, String? absolutePath) =>
      _invoke('setExternalModel', {'mode': object.mode, 'path': absolutePath});

  Future<void> setYaw(double yaw) => _invoke('setObjectYaw', {'yaw': yaw});

  Future<void> setOffset(double x, double z) =>
      _invoke('setObjectOffset', {'x': x, 'z': z});

  Future<void> resetPlacement() => _invoke('resetPlacement');

  Future<void> setMarkerSizeMm(double mm) =>
      _invoke('setMarkerSizeMm', {'mm': mm});

  Future<void> setScaleTrim(double trim) =>
      _invoke('setScaleTrim', {'trim': trim});

  /// Drives the native CameraX pause/resume from the Flutter app lifecycle.
  Future<void> setActive(bool active) =>
      _invoke('setActive', {'active': active});

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) =>
      _methods.invokeMethod(method, args).catchError((_) {});
}
