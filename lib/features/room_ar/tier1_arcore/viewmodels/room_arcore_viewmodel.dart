import 'dart:async';

import 'package:flutter/material.dart';

import '../../../../core/models/product/product_ar_metadata.dart';
import '../../marker_ar/room_ar_session_args.dart';
import '../../model_delivery/room_ar_model_service.dart';
import '../../model_delivery/room_ar_model_state.dart';
import '../models/room_arcore_frame.dart';
import '../services/room_arcore_channel.dart';

/// Owns every observable piece of Tier-1 markerless-ARCore UI state.
///
/// The View feeds it raw gesture positions (already normalized to the
/// `AndroidView`'s own size); this class forwards intent to the native engine
/// over [RoomArCoreChannel] and interprets its per-frame tracking/plane/anchor
/// state into honest, customer-facing guidance. All real surface detection,
/// hit-testing and anchoring happens natively (ARCore) — this class never
/// fabricates a placement.
///
/// Model delivery reuses the exact same [RoomArModelService] contract Tier 2/3
/// use: cache → integrity → last-known-good → bundled fallback (bundled only
/// exists for the four originally-approved products — every other product,
/// including any future Admin-created one, is external-only and fails
/// honestly, never with a substituted model).
class RoomArCoreViewModel extends ChangeNotifier {
  RoomArCoreViewModel({
    required RoomArSessionArgs args,
    RoomArCoreChannel? channel,
    RoomArModelService? modelService,
  }) : _channel = channel ?? RoomArCoreChannel(),
       // ignore: prefer_initializing_formals
       _args = args,
       // ignore: prefer_initializing_formals
       _modelService = modelService;

  final RoomArSessionArgs _args;
  final RoomArCoreChannel _channel;
  RoomArModelService? _modelService;

  String get firestoreProductId => _args.firestoreProductId;
  String get nativeMode => _args.nativeMode;
  String get productTitle => _args.productTitle;
  ProductArMetadata get metadata => _args.metadata;

  /// `true` only for one of the four originally-bundled products — the only
  /// case where a Storage delivery failure has a safe, byte-identical
  /// fallback to show instead of an honest failure.
  bool get _hasBundledFallback => _args.object != null;

  /// Launch args for the Tier-3 Interactive 3D Preview of this same
  /// product — used by the "View a 3D preview instead" fallback whenever
  /// ARCore itself cannot run on this device/session. Never null — every
  /// [RoomArCoreViewModel] is constructed from a fully eligible
  /// [RoomArSessionArgs].
  RoomArSessionArgs get fallbackPreviewArgs => _args;

  // ── frame-derived state ────────────────────────────────────────────────
  RoomArCoreFrame _frame = RoomArCoreFrame.starting;
  RoomArCoreFrame get frame => _frame;

  bool get tracking => _frame.tracking;
  bool get planesFound => _frame.planesFound;
  bool get hasAnchor => _frame.hasAnchor;
  bool get anchorTracking => _frame.anchorTracking;
  bool get reticleVisible => _frame.reticleVisible;
  String get guidanceMessage => _frame.guidanceMessage;

  /// A terminal, native-reported failure (camera permission / ARCore
  /// unavailable / installing / camera taken by another app) — the screen
  /// must show an honest full-screen state and offer the Tier-3 fallback,
  /// never a frozen or misleading camera view.
  bool get hasEngineError => _frame.hasTerminalError;
  String? get engineErrorMessage => _frame.error;

  /// `true` once Storage delivery has definitively failed for a product with
  /// no bundled fallback — this session can show no model at all, honestly,
  /// rather than ever substituting an unrelated one.
  bool get customerModelUnavailable => _customerModelUnavailable;
  bool _customerModelUnavailable = false;

  RoomArModelState _deliveryState = const RoomArModelIdle();
  RoomArModelSource? _deliverySource;
  RoomArModelState get deliveryState => _deliveryState;
  RoomArModelSource? get deliverySource => _deliverySource;

  /// The last Storage-verified file path handed to the native renderer, or
  /// `null` while nothing external has resolved yet (bundled products, or a
  /// resolve still pending/failed). Tracked purely so [onPlatformViewReady]
  /// can re-send it — see that method's doc comment.
  String? _resolvedExternalPath;

  String? _flash;
  String? get flash => _flash;
  Timer? _flashTimer;

  // ── rotation state ─────────────────────────────────────────────────────
  double _yaw = 0;
  double get yaw => _yaw;
  double get yawAtGestureStart => _yaw;

  void rotateTo(double yaw) {
    _yaw = _wrapPi(yaw);
    _channel.setYaw(_yaw * 180.0 / 3.141592653589793);
    _safeNotify();
  }

  // ── surface size (for normalizing gesture positions) ────────────────────
  Size _surface = Size.zero;
  void setSurfaceSize(Size size) => _surface = size;

  (double, double)? _normalize(Offset p) {
    final w = _surface.width;
    final h = _surface.height;
    if (w <= 0 || h <= 0) return null;
    return ((p.dx / w).clamp(0.0, 1.0), (p.dy / h).clamp(0.0, 1.0));
  }

  // ── placement gestures ───────────────────────────────────────────────────
  static const double tapSlopPx = 18.0;
  static const int tapMaxMs = 300;

  void placeAt(Offset p) {
    final n = _normalize(p);
    if (n == null) return;
    _channel.placeAt(n.$1, n.$2);
  }

  void beginDrag() {
    if (hasAnchor) _channel.beginReposition();
  }

  void dragTo(Offset p) {
    if (!hasAnchor) return;
    final n = _normalize(p);
    if (n == null) return;
    _channel.repositionTo(n.$1, n.$2);
  }

  void endDrag() {
    if (hasAnchor) _channel.endReposition();
  }

  void resetPlacement() {
    _yaw = 0;
    _channel.resetPlacement();
    _safeNotify();
  }

  // ── lifecycle ────────────────────────────────────────────────────────────
  StreamSubscription<RoomArCoreFrame>? _sub;
  bool _started = false;
  bool _disposed = false;
  bool _resolveRan = false;

  Future<void> start() async {
    if (_started) return;
    _started = true;

    _sub = _channel.frames().listen(_onFrame);
    await _channel.setObject(nativeMode);
    if (_hasBundledFallback) {
      // Show the bundled model immediately (the original four) — the
      // verified copy swaps in when ready, exactly like Tier 2/3.
      await _channel.setExternalModel(nativeMode, null);
    }
    unawaited(_resolveModel());
  }

  void _onFrame(RoomArCoreFrame f) {
    _frame = f;
    if (f.tapRejected) {
      // Honest visible feedback for a genuine initial-placement miss —
      // customer requirement, tracker §32. Reuses the existing flash
      // mechanism (same one "Showing the built-in 3D model" uses) rather
      // than adding a second, competing transient-message channel.
      _showFlash("Couldn't find a surface there — try tapping again");
      return; // _showFlash already notifies.
    }
    _safeNotify();
  }

  /// The Storage-delivery service resolves asynchronously (its cache dir
  /// opens via `path_provider`); the route attaches it once ready.
  void attachModelService(RoomArModelService service) {
    _modelService = service;
    if (_started) unawaited(_resolveModel());
    _safeNotify();
  }

  /// Called by the View once the native PlatformView actually exists
  /// (`AndroidView.onPlatformViewCreated`). The `mode` creation param is the
  /// primary path for the four originally-bundled products (selected
  /// synchronously during native construction — see
  /// `RoomArCoreModelRenderer`'s `initialMode`), but a Storage-delivered
  /// external model can only ever be set via a **post**-construction channel
  /// call, since the file isn't known until the download/cache resolve
  /// finishes — and that call can still race the platform view's own
  /// creation exactly like the bug this mirrors (tracker §16 "Admin-preview
  /// always shows the chair" / §22 "model never renders"). This is the
  /// guaranteed-post-creation re-send: harmless/idempotent if nothing raced
  /// (the renderer just re-applies the same state), and the only thing that
  /// actually saves the session if it did.
  void onPlatformViewReady() {
    _channel.setObject(nativeMode);
    final path = _resolvedExternalPath;
    if (path != null) _channel.setExternalModel(nativeMode, path);
  }

  Future<void> _resolveModel() async {
    final service = _modelService;
    if (service == null || _resolveRan || _disposed) return;
    _resolveRan = true;

    if (!metadata.isRenderable) {
      // Should never happen past the prep-screen eligibility gate.
      if (_hasBundledFallback) {
        _deliverySource = RoomArModelSource.bundledFallback;
        _deliveryState = const RoomArModelReady(
          source: RoomArModelSource.bundledFallback,
        );
      } else {
        _customerModelUnavailable = true;
      }
      _safeNotify();
      return;
    }

    _deliveryState = const RoomArModelCheckingCache();
    _safeNotify();

    final outcome = await service.resolve(
      productId: firestoreProductId,
      metadata: metadata,
      onState: (s) {
        if (_disposed) return;
        _deliveryState = s;
        _safeNotify();
      },
    );
    if (_disposed) return;

    if (outcome is RoomArModelReady && outcome.file != null) {
      _deliverySource = outcome.source;
      _resolvedExternalPath = outcome.file!.path;
      await _channel.setExternalModel(nativeMode, outcome.file!.path);
    } else if (_hasBundledFallback) {
      _deliverySource = RoomArModelSource.bundledFallback;
      await _channel.setExternalModel(nativeMode, null);
      _showFlash('Showing the built-in 3D model');
    } else {
      _customerModelUnavailable = true;
    }
    _safeNotify();
  }

  void setActive(bool active) => _channel.setActive(active);

  void _showFlash(String msg) {
    _flash = msg;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1600), () {
      _flash = null;
      _safeNotify();
    });
    _safeNotify();
  }

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _flashTimer?.cancel();
    _channel.setActive(false);
    super.dispose();
  }
}

double _wrapPi(double a) {
  const twoPi = 2 * 3.141592653589793;
  var v = a % twoPi;
  if (v > 3.141592653589793) v -= twoPi;
  if (v < -3.141592653589793) v += twoPi;
  return v;
}
