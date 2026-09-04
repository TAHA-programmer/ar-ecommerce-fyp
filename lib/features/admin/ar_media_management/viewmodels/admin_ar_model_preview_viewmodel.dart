import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart' show ChangeNotifier, visibleForTesting;
import 'package:path_provider/path_provider.dart';

import '../../../../core/models/product/product_ar_metadata.dart';
import '../../../../core/services/firebase_storage_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../room_ar/model_delivery/glb_inspector.dart';
import '../../../room_ar/preview/room_ar_preview_channel.dart';
import '../utils/admin_glb_validator.dart';

/// Route argument for the admin 3D preview (Phase 9.2 R16). Exactly one of
/// [localFilePath] / [metadata] is set — a staged, not-yet-uploaded GLB, or a
/// committed contract to download and preview.
class AdminArModelPreviewArgs {
  const AdminArModelPreviewArgs({
    this.localFilePath,
    this.metadata,
    required this.productTitle,
    required this.widthM,
    required this.depthM,
    required this.heightM,
  }) : assert(localFilePath != null || metadata != null);

  final String? localFilePath;
  final ProductArMetadata? metadata;
  final String productTitle;
  final double widthM;
  final double depthM;
  final double heightM;
}

/// Drives the shared native orbit renderer (`RoomArPreviewChannel`, key
/// `"admin"`) for the admin preview. A staged local `.glb` is handed straight
/// over; a committed model is downloaded through [StorageService], re-checked
/// (structure + bounding box), written to a temp file and handed over. No
/// camera, no marker, no customer-facing chrome.
class AdminArModelPreviewViewModel extends ChangeNotifier {
  AdminArModelPreviewViewModel({
    required this.args,
    RoomArPreviewChannel? channel,
    StorageService? storage,
    this._inspector = const GlbInspector(),
    @visibleForTesting Directory? tempDirectory,
  }) : _channel = channel ?? RoomArPreviewChannel(),
       _storage = storage ?? FirebaseStorageService(),
       _tempDirOverride = tempDirectory;

  final AdminArModelPreviewArgs args;
  final RoomArPreviewChannel _channel;
  final StorageService _storage;
  final GlbInspector _inspector;
  final Directory? _tempDirOverride;

  StreamSubscription<RoomArPreviewLoad>? _sub;
  bool _started = false;
  bool _disposed = false;
  File? _tempFile;

  RoomArPreviewLoad _nativeLoad = RoomArPreviewLoad.loading;
  bool _resolveFailed = false;
  String? _notice;

  /// The concrete on-disk `.glb` path to render — a staged local pick, or the
  /// downloaded-and-re-verified temp copy of a committed model. `null` until
  /// resolution finishes. The View builds the native PlatformView **only after
  /// this is set** and passes it as a creation param, so the first model shown
  /// is always the right one (a post-creation `setModel` channel call races the
  /// PlatformView's creation and gets dropped — that was the "always shows the
  /// chair until Reset view" bug).
  String? _resolvedFilePath;
  String? get resolvedFilePath => _resolvedFilePath;

  String get productTitle => args.productTitle;
  ({double w, double h, double d}) get dimensionsM =>
      (w: args.widthM, h: args.heightM, d: args.depthM);

  bool get renderFailed =>
      _resolveFailed || _nativeLoad == RoomArPreviewLoad.failed;
  bool get isPreparing =>
      !renderFailed &&
      (_resolvedFilePath == null || _nativeLoad == RoomArPreviewLoad.loading);
  String? get notice => _notice;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = _channel.loadStates().listen((s) {
      _nativeLoad = s;
      _safeNotify();
    });

    final localPath = args.localFilePath;
    if (localPath != null) {
      _resolvedFilePath = localPath;
    } else if (args.metadata != null) {
      await _resolveCommitted(args.metadata!);
    } else {
      _resolveFailed = true;
    }
    _safeNotify();
  }

  /// Called by the View once the native PlatformView actually exists
  /// (`onPlatformViewCreated`). The creation param is the primary path; this is
  /// a guaranteed-post-creation re-send so a device where creation params don't
  /// reach the factory still loads the right model. Idempotent — the renderer
  /// just re-loads the same file.
  void onRendererCreated() {
    final path = _resolvedFilePath;
    if (path != null) _channel.setModel('admin', path);
  }

  Future<void> _resolveCommitted(ProductArMetadata meta) async {
    try {
      final bytes = await _storage.downloadArModelBytes(
        meta.storagePath,
        maxSize: kArModelTransportMaxBytes,
      );
      final check = _inspector.inspect(
        bytes,
        expected: GlbExpectedBox(
          widthM: meta.widthM,
          depthM: meta.depthM,
          heightM: meta.heightM,
        ),
        maxBytes: kArModelTransportMaxBytes,
      );
      if (!check.ok) {
        _resolveFailed = true;
        _notice = 'The stored model failed verification and cannot be shown.';
        return;
      }
      final dir = _tempDirOverride ?? await getTemporaryDirectory();
      final f = File(
        '${dir.path}/admin_ar_preview_'
        '${meta.sha256.substring(0, meta.sha256.length.clamp(0, 12))}.glb',
      );
      await f.writeAsBytes(bytes, flush: true);
      _tempFile = f;
      _resolvedFilePath = f.path;
    } catch (_) {
      _resolveFailed = true;
      _notice =
          'Could not load the stored model. Client read of this product\'s '
          'AR object may be restricted — preview a freshly-picked file '
          'instead.';
    }
  }

  void orbit(double dx, double dy) => _channel.orbit(dx, dy);
  void pan(double dx, double dy) => _channel.pan(dx, dy);
  void zoom(double scale) => _channel.zoom(scale);
  void resetView() => _channel.resetView();
  void setActive(bool active) => _channel.setActive(active);

  void _safeNotify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _sub?.cancel();
    _channel.setActive(false);
    final temp = _tempFile;
    if (temp != null) {
      unawaited(temp.delete().then((_) {}, onError: (_) {}));
    }
    super.dispose();
  }
}
