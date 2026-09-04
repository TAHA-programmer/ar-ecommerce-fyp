import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../../../core/models/product/product_ar_metadata.dart';
import '../../room_ar_product_manifest.dart';
import '../room_ar_session_args.dart';
import '../../model_delivery/room_ar_model_service.dart';
import '../../model_delivery/room_ar_model_state.dart';
import '../models/marker_ar_config.dart';
import '../models/marker_ar_frame.dart';
import '../models/marker_ar_object.dart';
import '../models/marker_calibration.dart';
import '../services/marker_calibration_store.dart';
import '../services/room_ar_marker_channel.dart';
import '../utils/marker_placement_math.dart';

/// How the Marker-AR engine screen was opened.
enum MarkerArLaunchMode {
  /// Internal engine-verification surface (debug-only Profile tile): the
  /// four-product selector, the debug metrics HUD and the R10 Storage panel are
  /// all available (still `kDebugMode`-gated).
  engineDev,

  /// The customer "Start AR" launch for one approved product
  /// (Product Details → prep screen → here). No selector, no debug controls,
  /// no R10 panel — ever, in any build. The product's verified GLB is fetched
  /// from Storage on start, with the bundled asset as the silent fallback.
  customerProduct,
}

/// Owns every observable piece of Tier-2 Marker-AR UI state and every decision.
///
/// The View feeds it raw pointer coordinates + the live PlatformView size; this
/// class does the marker-floor ray casting, the 0.6 m origin clamp, the
/// customer-facing yaw and the honest rejection messaging, then drives the
/// native engine over [RoomArMarkerChannel]. All placement math is the
/// physically-approved PoC math (`marker_placement_math.dart`), unchanged.
class MarkerArViewModel extends ChangeNotifier {
  MarkerArViewModel({
    RoomArMarkerChannel? channel,
    MarkerCalibrationStore? calibrationStore,
    MarkerArObject initialObject = MarkerArObject.chair,
    RoomArModelService? roomArModelService,
    MarkerArLaunchMode mode = MarkerArLaunchMode.engineDev,
    ProductArMetadata? customerMetadata,
  }) : _channel = channel ?? RoomArMarkerChannel(),
       _calibrationStore = calibrationStore ?? MarkerCalibrationStore(),
       _object = initialObject,
       _modelService = roomArModelService,
       // ignore: prefer_initializing_formals
       _mode = mode,
       // ignore: prefer_initializing_formals
       _customerMetadata = customerMetadata;

  final MarkerArLaunchMode _mode;
  final ProductArMetadata? _customerMetadata;

  /// True for the customer single-product launch — the View hides the object
  /// selector and every developer control.
  bool get isCustomerMode => _mode == MarkerArLaunchMode.customerProduct;

  /// Launch args for the Tier-3 Interactive 3D Preview of this same product —
  /// used by the "View a 3D preview instead" fallback on the camera-permission
  /// and engine-unavailable screens. Null outside the customer flow.
  RoomArSessionArgs? get customerSessionArgs {
    final m = _customerMetadata;
    if (_mode != MarkerArLaunchMode.customerProduct || m == null) return null;
    return RoomArSessionArgs(
      object: _object,
      metadata: m,
      productTitle: _object.displayName,
    );
  }

  final RoomArMarkerChannel _channel;
  final MarkerCalibrationStore _calibrationStore;

  /// Phase 9.2 R10 — Firebase Storage GLB delivery. **Debug-only diagnostic
  /// wiring**: when null (release / customer builds, and every plain test) the
  /// engine runs exactly as before on the bundled GLBs. Never reached by the
  /// customer [MarkerArView] chrome — only the `kDebugMode` R10 panel.
  RoomArModelService? _modelService;

  /// Attach the Storage-delivery service after construction (its on-disk cache
  /// resolves asynchronously via `path_provider`).
  ///
  ///  * [MarkerArLaunchMode.engineDev]: debug-only wiring for the R10
  ///    verification panel — a no-op in release builds.
  ///  * [MarkerArLaunchMode.customerProduct]: the real production delivery path;
  ///    accepted in every build and it immediately resolves the product's model.
  void attachModelService(RoomArModelService service) {
    if (_mode == MarkerArLaunchMode.engineDev && !kDebugMode) return;
    _modelService = service;
    if (_mode == MarkerArLaunchMode.customerProduct) {
      unawaited(_resolveCustomerModel());
    }
    _safeNotify();
  }

  // ── customer single-product model delivery ───────────────────────────────
  RoomArModelState _deliveryState = const RoomArModelIdle();
  RoomArModelSource? _deliverySource;
  bool _customerResolveRan = false;

  /// The live Storage-delivery state for the customer's single product
  /// (checking cache → downloading → verifying → ready / offline / rejected).
  RoomArModelState get deliveryState => _deliveryState;

  /// Where the model actually came from once resolution settled, or `null`
  /// while still in flight. [RoomArModelSource.bundledFallback] means the
  /// byte-identical app-bundled GLB is in use (a delivery hiccup, not a
  /// customer-visible failure — the experience is unchanged).
  RoomArModelSource? get deliverySource => _deliverySource;

  Future<void> _resolveCustomerModel() async {
    if (_mode != MarkerArLaunchMode.customerProduct) return;
    final service = _modelService;
    if (service == null || _customerResolveRan) return;
    _customerResolveRan = true;

    final metadata =
        _customerMetadata ??
        RoomArProductManifest.byProductId[_object.firestoreProductId];

    if (metadata == null || !metadata.isRenderable) {
      // Should never happen past the prep-screen eligibility gate. Stay on the
      // bundled GLB rather than block the session.
      _deliverySource = RoomArModelSource.bundledFallback;
      _deliveryState = const RoomArModelReady(
        source: RoomArModelSource.bundledFallback,
      );
      await _channel.setExternalModel(_object, null);
      _safeNotify();
      return;
    }

    _deliveryState = const RoomArModelCheckingCache();
    _safeNotify();

    final outcome = await service.resolve(
      productId: _object.firestoreProductId,
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
      await _channel.setExternalModel(_object, outcome.file!.path);
    } else {
      // offline / rejected / failed / bundled → the app-bundled GLB is the
      // physically-approved, byte-identical fallback. Never a dead end.
      _deliverySource = RoomArModelSource.bundledFallback;
      await _channel.setExternalModel(_object, null);
      if (outcome is! RoomArModelReady) {
        _showFlash('Showing the built-in 3D model');
      }
    }
    _safeNotify();
  }

  // ── placement / interaction constants (validated on the Infinix) ──────────
  static const double safeRadiusM = 0.6; // 0.6 m safe-placement clamp
  static const double rejectRadiusM =
      1.5; // a tap beyond this is refused outright
  static const double tapSlopPx = 18.0;
  static const int tapMaxMs = 300;

  // ── lifecycle ────────────────────────────────────────────────────────────
  StreamSubscription<MarkerArFrame>? _sub;
  bool _started = false;
  bool _disposed = false;
  bool _engineConfigResolved = false;

  /// `true` once the one-shot native `config()` handshake has returned. Until
  /// then [config] is the fallback (which reports `openCvOk: false`), so the
  /// customer full-screen "AR unavailable" takeover must wait for this.
  bool get engineConfigResolved => _engineConfigResolved;

  // ── engine config + calibration ──────────────────────────────────────────
  MarkerArConfig _config = MarkerArConfig.fallback;
  MarkerArConfig get config => _config;

  MarkerCalibration _calibration = MarkerCalibration.initial;
  MarkerCalibration get calibration => _calibration;
  bool get isCalibrated => _calibration.isCalibrated;

  // ── frame-derived state ──────────────────────────────────────────────────
  MarkerArFrame _frame = MarkerArFrame.starting;
  MarkerArFrame get frame => _frame;

  MarkerTrackState get track => _frame.track;
  MarkerArStatus get status => _frame.status;
  bool get hasEngineError =>
      _frame.status == MarkerArStatus.error || !_config.openCvOk;
  String? get engineErrorMessage => !_config.openCvOk
      ? 'AR engine unavailable on this device (OpenCV failed to load).'
      : _frame.message;

  MarkerPose? _lastPose;
  List<double>? _lastCorners;
  bool _wasTracking = false;

  // ── selection + placement ────────────────────────────────────────────────
  MarkerArObject _object;
  MarkerArObject get object => _object;

  double _yaw = 0;
  double get yaw => _yaw;

  // marker floor plane offsets (metres, marker frame: X = _offX, Y = _offZ)
  double _offX = 0, _offZ = 0;
  double get offX => _offX;
  double get offZ => _offZ;

  bool _placed = false;
  bool get placementSet => _placed;

  Size _surface = Size.zero;

  // one-finger drag: model offset − grabbed floor point
  (double, double)? _dragGrab;

  // ── transient flash message ──────────────────────────────────────────────
  String? _flash;
  String? get flash => _flash;
  Timer? _flashTimer;

  // ── debug metrics HUD (development builds only) ──────────────────────────
  // fps / detection time / intrinsics / pose — independently useful for field
  // diagnostics, so kept; still `kDebugMode`-gated so it never ships to a
  // customer build. No QA cube: the production engine renders the four
  // approved products only.
  bool _debugHud = false;
  bool get debugAvailable =>
      kDebugMode && _mode == MarkerArLaunchMode.engineDev;
  bool get debugHudVisible => debugAvailable && _debugHud;
  void toggleDebugHud() {
    if (!debugAvailable) return;
    _debugHud = !_debugHud;
    notifyListeners();
  }

  /// The products offered in the selector: all four in the engine-dev surface,
  /// only the launched product in the customer flow (the View hides the
  /// selector entirely there).
  List<MarkerArObject> get selectableObjects =>
      isCustomerMode ? [_object] : MarkerArObject.values;

  // ── R10 — Firebase Storage GLB delivery (debug verification surface) ──────
  // Everything below is `kDebugMode` + `_modelService != null` gated. It lets
  // the developer exercise, product-by-product, the full delivery path:
  // bundled fallback → downloading → verified cache → last-known-good →
  // integrity/bounds rejection → offline → retry — and hand a verified
  // external file to the native renderer. Customer entry points stay disabled.

  bool get r10Available =>
      kDebugMode &&
      _mode == MarkerArLaunchMode.engineDev &&
      _modelService != null;

  final Map<MarkerArObject, RoomArModelState> _r10State = {};
  final Map<MarkerArObject, List<String>> _r10History = {};
  final Map<MarkerArObject, RoomArModelSource> _r10ActiveSource = {};
  final Set<MarkerArObject> _r10Busy = {};

  /// When true, a non-`Ready` remote outcome falls the native renderer back to
  /// the bundled GLB for that product (the temporary R10 rollback path). The
  /// rejection/offline reason still shows in the history.
  bool r10FallbackToBundled = true;

  RoomArModelState r10StateFor(MarkerArObject o) =>
      _r10State[o] ?? const RoomArModelIdle();
  List<String> r10HistoryFor(MarkerArObject o) =>
      List.unmodifiable(_r10History[o] ?? const []);
  RoomArModelSource? r10ActiveSourceFor(MarkerArObject o) =>
      _r10ActiveSource[o];
  bool r10IsBusy(MarkerArObject o) => _r10Busy.contains(o);

  /// Resolve [product] from Firebase Storage and, on success, hand the verified
  /// file to the native renderer. Uses [RoomArProductManifest] as the internal
  /// four-product verification source (live Firestore metadata is a later
  /// controlled write).
  Future<void> r10Resolve(MarkerArObject product) async {
    final service = _modelService;
    if (!r10Available || service == null || _r10Busy.contains(product)) return;
    final metadata =
        RoomArProductManifest.byProductId[product.firestoreProductId];
    if (metadata == null) {
      _r10State[product] = const RoomArModelFailed(
        'No manifest entry for this product.',
      );
      _safeNotify();
      return;
    }

    _r10Busy.add(product);
    _r10History[product] = <String>[];
    _r10State[product] = const RoomArModelCheckingCache();
    _safeNotify();

    final outcome = await service.resolve(
      productId: product.firestoreProductId,
      metadata: metadata,
      onState: (s) {
        _r10State[product] = s;
        (_r10History[product] ??= <String>[]).add(s.debugLabel);
        _safeNotify();
      },
    );

    if (_disposed) return;
    if (outcome is RoomArModelReady && outcome.file != null) {
      _r10ActiveSource[product] = outcome.source;
      await _channel.setExternalModel(product, outcome.file!.path);
    } else if (r10FallbackToBundled) {
      _r10ActiveSource[product] = RoomArModelSource.bundledFallback;
      (_r10History[product] ??= <String>[]).add('→ bundled fallback');
      await _channel.setExternalModel(product, null);
    }
    _r10Busy.remove(product);
    _safeNotify();
  }

  /// Tell the native renderer to render the **bundled** GLB for [product] and
  /// clear the R10 override/state for it. This does **not** touch the on-disk
  /// cache — the next [r10Resolve] will still be served from the verified cache
  /// entry if one exists. To exercise the download / offline / last-known-good
  /// path, evict the cache entry first ([r10EvictCache]).
  Future<void> r10UseBundledModel(MarkerArObject product) async {
    if (!r10Available) return;
    _r10ActiveSource.remove(product);
    _r10State[product] = const RoomArModelIdle();
    _r10History[product] = <String>[];
    await _channel.setExternalModel(product, null);
    _safeNotify();
  }

  /// Debug-only: delete the exact versioned verified-cache entry for [product]
  /// (path + version + SHA-256), **keeping** its last-known-good copy. After
  /// this the next [r10Resolve] must download; offline, it falls to
  /// last-known-good. Never exposed in a release / customer build.
  Future<void> r10EvictCache(MarkerArObject product) async {
    final service = _modelService;
    if (!r10Available || service == null || _r10Busy.contains(product)) return;
    final metadata =
        RoomArProductManifest.byProductId[product.firestoreProductId];
    if (metadata == null) return;
    await service.evictCachedEntry(
      productId: product.firestoreProductId,
      metadata: metadata,
    );
    (_r10History[product] ??= <String>[]).add('cache entry evicted (LKG kept)');
    _safeNotify();
  }

  // ── derived display helpers ──────────────────────────────────────────────

  /// Real-world W×D×H (cm) for the current object, including the calibration trim.
  ({double w, double d, double h}) get currentDimensionsCm {
    final dims = _config.dimsFor(_object); // [W(X), H(Y), D(Z)] metres
    final t = _calibration.scaleTrim;
    return (w: dims[0] * 100 * t, d: dims[2] * 100 * t, h: dims[1] * 100 * t);
  }

  // ── startup ──────────────────────────────────────────────────────────────
  Future<void> start() async {
    if (_started) return;
    _started = true;

    _config = await _channel.config();
    _engineConfigResolved = true;
    _calibration = await _calibrationStore.load();
    if (_disposed) return;

    await _channel.setObject(_object);
    await _channel.setMarkerSizeMm(_calibration.markerSizeMm);
    await _channel.setScaleTrim(_calibration.scaleTrim);
    await _channel.setYaw(_yaw);

    _sub = _channel.frames().listen(
      _onFrame,
      onError: (Object e) {
        _frame = MarkerArFrame.fromMap({
          'state': 'error',
          'message': e.toString(),
        });
        _safeNotify();
      },
    );
    _safeNotify();

    // Customer flow: fetch this product's verified GLB from Storage now (the
    // service may also have been attached before start()).
    if (_mode == MarkerArLaunchMode.customerProduct && _modelService != null) {
      unawaited(_resolveCustomerModel());
    }
  }

  void _onFrame(MarkerArFrame f) {
    _frame = f;

    // adopt a fresh pose only on a genuine detection
    final pose = f.pose;
    if (pose != null) {
      _lastPose = pose;
      _lastCorners = f.corners;
    }

    switch (f.track) {
      case MarkerTrackState.tracking:
        if (!_wasTracking) _wasTracking = true;
      case MarkerTrackState.holding:
        _wasTracking = false;
      case MarkerTrackState.tooFar:
      case MarkerTrackState.searching:
        _wasTracking = false;
        _lastPose = null;
        _lastCorners = null;
    }
    _safeNotify();
  }

  // ── app lifecycle → native camera ────────────────────────────────────────
  void setActive(bool active) => _channel.setActive(active);

  // ── view feeds ───────────────────────────────────────────────────────────
  void setSurfaceSize(Size size) => _surface = size;

  List<double>? get markerCornersImage => _lastCorners;

  // ── selection ────────────────────────────────────────────────────────────
  void selectObject(MarkerArObject next) {
    if (next == _object) return;
    _object = next;
    _channel.setObject(next);
    _safeNotify();
  }

  // ── rotation ─────────────────────────────────────────────────────────────
  void setYaw(double v) {
    _yaw = wrapPi(v);
    _channel.setYaw(_yaw);
    _safeNotify();
  }

  void rotateTo(double yaw) => setYaw(yaw);

  double get yawAtGestureStart => _yaw;

  // ── floor ray casting ────────────────────────────────────────────────────

  /// Cast surface point [p] onto the marker floor plane, or null if that can't
  /// be done honestly right now (not tracking / no pose / no intrinsics / ray
  /// misses or grazes the floor / behind the camera).
  FloorHit? floorAt(Offset p) {
    final pose = _lastPose;
    if (pose == null || _frame.track != MarkerTrackState.tracking) return null;
    if (!_frame.hasIntrinsics) return null;
    if (_surface.width == 0 || _surface.height == 0) return null;
    final crop = CropMap(
      surfaceW: _surface.width,
      surfaceH: _surface.height,
      imgW: _frame.imgW,
      imgH: _frame.imgH,
    );
    return screenToMarkerFloor(
      sx: p.dx,
      sy: p.dy,
      crop: crop,
      fx: _frame.k[0],
      fy: _frame.k[1],
      r: pose.r,
      t: pose.t,
    );
  }

  // ── tap-to-place ─────────────────────────────────────────────────────────
  void placeAt(Offset p) {
    if (_frame.track != MarkerTrackState.tracking) {
      _showFlash('Point at the marker, then tap the floor to place');
      return;
    }
    final hit = floorAt(p);
    if (hit == null) {
      _showFlash("Can't place there — aim at the floor near the marker");
      return;
    }
    if (hit.radius > rejectRadiusM) {
      _showFlash(
        'Too far from the marker (${hit.radius.toStringAsFixed(1)} m) — '
        'tap closer to it',
      );
      return;
    }
    final (nx, nz) = clampToRadius(hit.offX, hit.offZ, safeRadiusM);
    final pose = _lastPose!;
    final yaw = wrapPi(
      faceCameraYaw(
        r: pose.r,
        t: pose.t,
        offX: nx,
        offZ: nz,
        fallbackYaw: _yaw,
      ),
    );
    _offX = nx;
    _offZ = nz;
    _yaw = yaw;
    _placed = true;
    _channel.setOffset(_offX, _offZ);
    _channel.setYaw(_yaw);
    _showFlash(
      hit.radius > safeRadiusM ? 'Placed — clamped to 0.6 m' : 'Placed',
    );
  }

  // ── one-finger floor drag ────────────────────────────────────────────────
  void beginDrag() => _dragGrab = null;

  void dragTo(Offset p) {
    if (_dragGrab == null) {
      final g = floorAt(p);
      if (g != null) _dragGrab = (_offX - g.offX, _offZ - g.offZ);
    }
    final f = floorAt(p);
    final grab = _dragGrab;
    if (f == null || grab == null) return;
    final (nx, nz) = clampToRadius(
      f.offX + grab.$1,
      f.offZ + grab.$2,
      safeRadiusM,
    );
    _offX = nx;
    _offZ = nz;
    _placed = true;
    _channel.setOffset(_offX, _offZ);
    _safeNotify();
  }

  void endDrag() => _dragGrab = null;

  // ── face me / reset ──────────────────────────────────────────────────────
  void faceMe() {
    final pose = _lastPose;
    if (pose == null || _frame.track != MarkerTrackState.tracking) {
      _showFlash('Point at the marker first');
      return;
    }
    final yaw = wrapPi(
      faceCameraYaw(
        r: pose.r,
        t: pose.t,
        offX: _offX,
        offZ: _offZ,
        fallbackYaw: _yaw,
      ),
    );
    _yaw = yaw;
    _channel.setYaw(yaw);
    _safeNotify();
  }

  void reset() {
    final pose = _lastPose;
    final yaw = pose == null
        ? 0.0
        : wrapPi(faceCameraYaw(r: pose.r, t: pose.t, fallbackYaw: 0));
    _yaw = yaw;
    _offX = 0;
    _offZ = 0;
    _placed = true;
    _channel.resetPlacement(); // native: offset 0,0
    _channel.setYaw(yaw); // then face the customer
    _safeNotify();
  }

  // ── calibration ──────────────────────────────────────────────────────────
  Future<void> setMarkerSizeMm(double mm) async {
    _calibration = _calibration.copyWith(markerSizeMm: mm);
    await _channel.setMarkerSizeMm(_calibration.markerSizeMm);
    await _calibrationStore.save(_calibration);
    _safeNotify();
  }

  Future<void> setScaleTrim(double trim) async {
    _calibration = _calibration.copyWith(scaleTrim: trim);
    await _channel.setScaleTrim(_calibration.scaleTrim);
    await _calibrationStore.save(_calibration);
    _safeNotify();
  }

  Future<void> setCalibrationConfirmed(bool confirmed) async {
    _calibration = _calibration.copyWith(confirmed: confirmed);
    await _calibrationStore.save(_calibration);
    _safeNotify();
  }

  Future<void> resetCalibration() async {
    _calibration = MarkerCalibration.initial;
    await _channel.setMarkerSizeMm(_calibration.markerSizeMm);
    await _channel.setScaleTrim(_calibration.scaleTrim);
    await _calibrationStore.save(_calibration);
    _safeNotify();
  }

  // ── printable marker ─────────────────────────────────────────────────────
  Future<Uint8List> markerPng({int px = 1400}) => _channel.markerPng(px: px);

  // ── flash ────────────────────────────────────────────────────────────────
  void _showFlash(String msg) {
    _flash = msg;
    _flashTimer?.cancel();
    _flashTimer = Timer(const Duration(milliseconds: 1300), () {
      _flash = null;
      _safeNotify();
    });
    _safeNotify();
  }

  void _safeNotify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _flashTimer?.cancel();
    // Release the native camera even if the PlatformView is torn down out of
    // order — the native view's own dispose() also unbinds CameraX, so this is
    // a cheap belt-and-braces (and a no-op once the view is gone).
    _channel.setActive(false);
    super.dispose();
  }
}
