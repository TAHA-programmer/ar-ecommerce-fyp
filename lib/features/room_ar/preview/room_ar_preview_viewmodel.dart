import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../core/models/product/product_ar_metadata.dart';
import '../marker_ar/models/marker_ar_object.dart';
import '../marker_ar/room_ar_session_args.dart';
import '../model_delivery/room_ar_model_service.dart';
import '../model_delivery/room_ar_model_state.dart';
import '../room_ar_product_manifest.dart';
import 'room_ar_preview_channel.dart';

/// Owns the Tier-3 Interactive 3D Preview state for **one** approved product.
///
/// Resolves that product's GLB through the same verified [RoomArModelService]
/// the Tier-2 session uses (cache → integrity → last-known-good → bundled
/// fallback), hands the file (or `null` = bundled) to the native orbit renderer,
/// and forwards orbit / pan / pinch / reset gestures. No camera, no marker, no
/// developer controls.
class RoomArPreviewViewModel extends ChangeNotifier {
  RoomArPreviewViewModel({
    required RoomArSessionArgs args,
    RoomArPreviewChannel? channel,
    RoomArModelService? modelService,
  }) : _channel = channel ?? RoomArPreviewChannel(),
       // ignore: prefer_initializing_formals
       _args = args,
       // ignore: prefer_initializing_formals
       _modelService = modelService;

  final RoomArSessionArgs _args;
  final RoomArPreviewChannel _channel;
  RoomArModelService? _modelService;

  StreamSubscription<RoomArPreviewLoad>? _sub;
  bool _started = false;
  bool _disposed = false;
  bool _resolveRan = false;

  MarkerArObject get object => _args.object;
  String get productTitle => _args.productTitle;
  ProductArMetadata get metadata => _args.metadata;

  /// `[width, height, depth]` metres of the validated model — for the honest
  /// "shown at actual size" caption.
  ({double w, double h, double d}) get dimensionsM {
    final m = _args.metadata;
    return (w: m.widthM, h: m.heightM, d: m.depthM);
  }

  RoomArPreviewLoad _nativeLoad = RoomArPreviewLoad.loading;
  RoomArModelState _deliveryState = const RoomArModelIdle();
  RoomArModelSource? _deliverySource;

  RoomArModelState get deliveryState => _deliveryState;
  RoomArModelSource? get deliverySource => _deliverySource;

  /// The renderer reported it cannot display any model at all. The bundled GLB
  /// is compiled in, so this only happens on a genuine device/renderer failure.
  bool get renderFailed => _nativeLoad == RoomArPreviewLoad.failed;

  /// The native renderer hasn't shown a model yet (first load). The Storage
  /// verified-copy swap happens transparently behind this.
  bool get isPreparing =>
      _nativeLoad == RoomArPreviewLoad.loading && !renderFailed;

  String? _notice;
  String? get notice => _notice;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _sub = _channel.loadStates().listen((s) {
      _nativeLoad = s;
      _safeNotify();
    });

    // Show the bundled model immediately; the verified copy swaps in when ready.
    await _channel.setModel(object.mode, null);
    unawaited(_resolveModel());
    _safeNotify();
  }

  /// The Storage-delivery service resolves asynchronously (its cache dir opens
  /// via `path_provider`); the route attaches it once it's ready.
  void attachModelService(RoomArModelService service) {
    _modelService = service;
    if (_started) unawaited(_resolveModel());
    _safeNotify();
  }

  Future<void> _resolveModel() async {
    final service = _modelService;
    if (service == null || _resolveRan || _disposed) return;
    _resolveRan = true;

    final meta =
        RoomArProductManifest.byProductId[object.firestoreProductId] ??
        _args.metadata;
    if (!meta.isRenderable) {
      _deliverySource = RoomArModelSource.bundledFallback;
      _safeNotify();
      return;
    }

    _deliveryState = const RoomArModelCheckingCache();
    _safeNotify();

    final outcome = await service.resolve(
      productId: object.firestoreProductId,
      metadata: meta,
      onState: (s) {
        if (_disposed) return;
        _deliveryState = s;
        _safeNotify();
      },
    );
    if (_disposed) return;

    if (outcome is RoomArModelReady && outcome.file != null) {
      _deliverySource = outcome.source;
      await _channel.setModel(object.mode, outcome.file!.path);
    } else {
      _deliverySource = RoomArModelSource.bundledFallback;
      await _channel.setModel(object.mode, null);
      if (outcome is RoomArModelOffline) {
        _notice = 'You\'re offline — showing the built-in 3D model.';
      } else if (outcome is! RoomArModelReady) {
        _notice = 'Showing the built-in 3D model.';
      }
    }
    _safeNotify();
  }

  // ── gestures (forwarded to the native orbit renderer) ───────────────────
  void orbit(double dxPx, double dyPx) => _channel.orbit(dxPx, dyPx);
  void pan(double dxPx, double dyPx) => _channel.pan(dxPx, dyPx);
  void zoom(double scale) => _channel.zoom(scale);
  void resetView() => _channel.resetView();

  // ── lifecycle ──────────────────────────────────────────────────────────
  void setActive(bool active) => _channel.setActive(active);

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _channel.setActive(false);
    super.dispose();
  }
}
