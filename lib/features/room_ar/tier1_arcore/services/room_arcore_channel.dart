import 'dart:async';

import 'package:flutter/services.dart';

import '../models/room_arcore_frame.dart';

/// Thin Dart ↔ platform boundary for the Tier-1 markerless-ARCore native
/// engine (`RoomArCorePlugin.kt`). **No business logic** — it only marshals
/// calls and decodes the event stream; `RoomArCoreViewModel` owns every
/// observable state and decision. Mirrors `RoomArMarkerChannel`'s contract.
class RoomArCoreChannel {
  static const String _methodsName = 'twin_ar/room_ar/arcore/methods';
  static const String _eventsName = 'twin_ar/room_ar/arcore/events';

  /// The PlatformView type string for `AndroidView(viewType: ...)`.
  static const String viewType = 'twin_ar/room_ar/arcore/view';

  final MethodChannel _methods;
  final EventChannel _events;

  RoomArCoreChannel({MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? const MethodChannel(_methodsName),
      _events = events ?? const EventChannel(_eventsName);

  /// The broadcast stream of per-frame tracking / plane / anchor state.
  Stream<RoomArCoreFrame> frames() => _events.receiveBroadcastStream().map(
    (e) => RoomArCoreFrame.fromMap(e as Map<dynamic, dynamic>),
  );

  /// [mode] is the native renderer key: `chair`/`table`/`lamp`/`sofa` for the
  /// four bundled products, or the live Firestore product id for every other
  /// product — see `RoomArSessionArgs.nativeMode`.
  Future<void> setObject(String mode) => _invoke('setArMode', {'mode': mode});

  /// Hand the native renderer a **verified** external GLB ([absolutePath],
  /// from `RoomArModelService`) for [mode], or pass null to drop the override
  /// and fall back to the bundled asset (if one exists for this key).
  Future<void> setExternalModel(String mode, String? absolutePath) =>
      _invoke('setExternalModel', {'mode': mode, 'path': absolutePath});

  /// Place (or, once already placed, this same op replaces) the product at
  /// the real ARCore hit-test under normalized view-fraction point
  /// ([fx], [fy] each in 0..1) — device-pixel-ratio independent by
  /// construction.
  Future<void> placeAt(double fx, double fy) =>
      _invoke('placeAt', {'fx': fx, 'fy': fy});

  Future<void> beginReposition() => _invoke('beginReposition');

  Future<void> repositionTo(double fx, double fy) =>
      _invoke('repositionTo', {'fx': fx, 'fy': fy});

  Future<void> endReposition() => _invoke('endReposition');

  Future<void> setYaw(double degrees) =>
      _invoke('setYaw', {'degrees': degrees});

  /// Removes the placed anchor (Reset / Remove).
  Future<void> resetPlacement() => _invoke('resetPlacement');

  /// Drives the native ARCore session pause/resume from the Flutter app
  /// lifecycle.
  Future<void> setActive(bool active) =>
      _invoke('setActive', {'active': active});

  Future<void> _invoke(String method, [Map<String, dynamic>? args]) =>
      _methods.invokeMethod(method, args).catchError((_) {});
}
