import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_service.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_state.dart';
import 'package:twin_ar/features/room_ar/room_ar_product_manifest.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_config.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_frame.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_calibration.dart';
import 'package:twin_ar/features/room_ar/marker_ar/services/marker_calibration_store.dart';
import 'package:twin_ar/features/room_ar/marker_ar/services/room_ar_marker_channel.dart';
import 'package:twin_ar/features/room_ar/marker_ar/viewmodels/marker_ar_viewmodel.dart';

/// In-memory stand-in for the native boundary. Records every call and lets the
/// test drive the frame stream.
class FakeRoomArMarkerChannel implements RoomArMarkerChannel {
  FakeRoomArMarkerChannel({MarkerArConfig? config})
    : _config = config ?? _defaultConfig;

  static final _defaultConfig = MarkerArConfig.fromMap(const {
    'openCvOk': true,
    'openCvVersion': '4.12.0',
    'dict': 'DICT_5X5_100',
    'markerId': 0,
    'markerMm': 160.0,
    'chairDims': [0.70, 0.82, 0.72],
    'tableDims': [0.90, 0.42, 0.90],
    'lampDims': [0.20, 0.45, 0.20],
    'sofaDims': [2.65, 0.82, 1.65],
  });

  final MarkerArConfig _config;
  final _frames = StreamController<MarkerArFrame>.broadcast();
  final List<String> calls = [];

  MarkerArObject? lastObject;
  double? lastYaw;
  (double, double)? lastOffset;
  double? lastMarkerMm;
  double? lastTrim;
  bool? lastActive;
  int resetCount = 0;

  void emit(MarkerArFrame f) => _frames.add(f);

  @override
  Future<MarkerArConfig> config() async {
    calls.add('config');
    return _config;
  }

  @override
  Stream<MarkerArFrame> frames() => _frames.stream;

  @override
  Future<Uint8List> markerPng({int px = 1400}) async => Uint8List(4);

  @override
  Future<void> setObject(MarkerArObject object) async {
    calls.add('setObject:${object.name}');
    lastObject = object;
  }

  (MarkerArObject, String?)? lastExternalModel;

  @override
  Future<void> setExternalModel(
    MarkerArObject object,
    String? absolutePath,
  ) async {
    calls.add('setExternalModel:${object.name}:${absolutePath ?? 'null'}');
    lastExternalModel = (object, absolutePath);
  }

  @override
  Future<void> setYaw(double yaw) async {
    calls.add('setYaw');
    lastYaw = yaw;
  }

  @override
  Future<void> setOffset(double x, double z) async {
    calls.add('setOffset');
    lastOffset = (x, z);
  }

  @override
  Future<void> resetPlacement() async {
    calls.add('resetPlacement');
    resetCount++;
  }

  @override
  Future<void> setMarkerSizeMm(double mm) async {
    calls.add('setMarkerSizeMm');
    lastMarkerMm = mm;
  }

  @override
  Future<void> setScaleTrim(double trim) async {
    calls.add('setScaleTrim');
    lastTrim = trim;
  }

  @override
  Future<void> setActive(bool active) async {
    calls.add('setActive:$active');
    lastActive = active;
  }

  Future<void> close() => _frames.close();
}

class _FakeModelService implements RoomArModelService {
  RoomArModelState outcome = const RoomArModelOffline();
  final List<String> resolvedProductIds = [];
  final List<String> evictedProductIds = [];

  @override
  Future<void> evictCachedEntry({
    required String productId,
    required ProductArMetadata metadata,
  }) async {
    evictedProductIds.add(productId);
  }

  @override
  Future<RoomArModelState> resolve({
    required String productId,
    required ProductArMetadata metadata,
    void Function(RoomArModelState state)? onState,
  }) async {
    resolvedProductIds.add(productId);
    onState?.call(const RoomArModelDownloading());
    onState?.call(outcome);
    return outcome;
  }

  @override
  Future<RoomArModelReady?> cachedOnly({
    required String productId,
    required ProductArMetadata metadata,
  }) async => outcome is RoomArModelReady ? outcome as RoomArModelReady : null;
}

// top-down pose: camera 1 m above the marker looking straight down.
MarkerArFrame trackingFrame({
  List<double> r = const [1, 0, 0, 0, -1, 0, 0, 0, -1],
  List<double> t = const [0, 0, 1],
}) => MarkerArFrame.fromMap({
  'track': 'tracking',
  'state': 'detected',
  'R': r,
  't': t,
  'K': [1000.0, 1000.0, 360.0, 640.0],
  'imgW': 720,
  'imgH': 1280,
  'distM': 1.0,
  'fps': 20.0,
  'markerSidePx': 110.0,
});

final holdingFrame = MarkerArFrame.fromMap(const {
  'track': 'holding',
  'state': 'detected',
  'heldMs': 500.0,
});
final searchingFrame = MarkerArFrame.fromMap(const {
  'track': 'searching',
  'state': 'searching',
});

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late FakeRoomArMarkerChannel channel;
  late MarkerArViewModel vm;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    channel = FakeRoomArMarkerChannel();
    vm = MarkerArViewModel(
      channel: channel,
      calibrationStore: MarkerCalibrationStore(),
    );
  });

  tearDown(() async {
    vm.dispose();
    await channel.close();
  });

  Future<void> startAndSettle() async {
    await vm.start();
    vm.setSurfaceSize(const Size(720, 1280));
  }

  group('startup', () {
    test('loads config + calibration and pushes them to the engine', () async {
      await startAndSettle();
      expect(channel.calls, contains('config'));
      expect(channel.lastObject, MarkerArObject.chair);
      expect(channel.lastMarkerMm, 160.0);
      expect(channel.lastTrim, 1.0);
      expect(vm.config.openCvOk, isTrue);
      expect(vm.isCalibrated, isFalse);
    });

    test('start is idempotent', () async {
      await vm.start();
      final n = channel.calls.where((c) => c == 'config').length;
      await vm.start();
      expect(channel.calls.where((c) => c == 'config').length, n);
    });

    test('surfaces an engine error when OpenCV is unavailable', () async {
      final badChannel = FakeRoomArMarkerChannel(
        config: MarkerArConfig.fromMap(const {'openCvOk': false}),
      );
      final badVm = MarkerArViewModel(channel: badChannel);
      await badVm.start();
      expect(badVm.hasEngineError, isTrue);
      expect(badVm.engineErrorMessage, contains('unavailable'));
      badVm.dispose();
      await badChannel.close();
    });
  });

  group('frame → state mapping', () {
    test('adopts a fresh pose only while genuinely tracking', () async {
      await startAndSettle();
      channel.emit(trackingFrame());
      await Future<void>.delayed(Duration.zero);
      expect(vm.track, MarkerTrackState.tracking);
      expect(vm.floorAt(const Offset(360, 640)), isNotNull);

      channel.emit(holdingFrame);
      await Future<void>.delayed(Duration.zero);
      expect(vm.track, MarkerTrackState.holding);
      // a held pose must never be usable for placement
      expect(vm.floorAt(const Offset(360, 640)), isNull);

      channel.emit(searchingFrame);
      await Future<void>.delayed(Duration.zero);
      expect(vm.track, MarkerTrackState.searching);
      expect(vm.floorAt(const Offset(360, 640)), isNull);
    });
  });

  group('tap-to-place', () {
    test(
      'places under the finger, clamps to 0.6 m and faces the camera',
      () async {
        await startAndSettle();
        channel.emit(trackingFrame());
        await Future<void>.delayed(Duration.zero);

        // 100 px right of centre → 0.10 m along marker +X at fx=1000, z=1 m.
        vm.placeAt(const Offset(460, 640));
        expect(vm.placementSet, isTrue);
        expect(vm.offX, closeTo(0.10, 1e-6));
        expect(vm.offZ, closeTo(0.0, 1e-6));
        expect(channel.lastOffset!.$1, closeTo(0.10, 1e-6));
        expect(vm.flash, 'Placed');
      },
    );

    test(
      'a tap far out on the floor is refused outright (not clamped)',
      () async {
        await startAndSettle();
        // camera 3 m up → a tap 800 px off-centre lands ~2.4 m out (> 1.5 m).
        channel.emit(trackingFrame(t: const [0, 0, 3]));
        await Future<void>.delayed(Duration.zero);

        vm.placeAt(const Offset(360 + 800, 640));
        expect(vm.placementSet, isFalse);
        expect(vm.flash, contains('Too far'));
      },
    );

    test('a tap while not tracking is rejected with guidance', () async {
      await startAndSettle();
      channel.emit(searchingFrame);
      await Future<void>.delayed(Duration.zero);
      vm.placeAt(const Offset(360, 640));
      expect(vm.placementSet, isFalse);
      expect(vm.flash, contains('Point at the marker'));
    });
  });

  group('drag / rotate / face me / reset', () {
    test(
      'drag keeps the grabbed floor point under the finger, clamped',
      () async {
        await startAndSettle();
        channel.emit(trackingFrame());
        await Future<void>.delayed(Duration.zero);

        vm.beginDrag();
        vm.dragTo(const Offset(360, 640)); // grab at origin
        vm.dragTo(const Offset(360 + 1000, 640)); // 1.0 m out → clamps to 0.6
        expect(vm.offX, closeTo(0.6, 1e-6));
        vm.endDrag();
      },
    );

    test('setYaw wraps and forwards to the engine', () async {
      await startAndSettle();
      vm.setYaw(4.0); // > pi
      expect(vm.yaw, lessThan(3.1416));
      expect(vm.yaw, greaterThan(-3.1416));
      expect(channel.lastYaw, vm.yaw);
    });

    test('reset recentres on the marker and faces the customer', () async {
      await startAndSettle();
      channel.emit(trackingFrame());
      await Future<void>.delayed(Duration.zero);
      vm.placeAt(const Offset(460, 640));
      expect(vm.offX, isNot(0));

      vm.reset();
      expect(vm.offX, 0);
      expect(vm.offZ, 0);
      expect(vm.placementSet, isTrue);
      expect(channel.resetCount, 1);
    });

    test('faceMe is rejected when not tracking', () async {
      await startAndSettle();
      channel.emit(searchingFrame);
      await Future<void>.delayed(Duration.zero);
      vm.faceMe();
      expect(vm.flash, contains('Point at the marker'));
    });
  });

  group('selection', () {
    test(
      'selecting an object swaps the native mode and current dims',
      () async {
        await startAndSettle();
        vm.selectObject(MarkerArObject.sofa);
        expect(channel.lastObject, MarkerArObject.sofa);
        final d = vm.currentDimensionsCm;
        expect(d.w, closeTo(265, 1e-6));
        expect(d.d, closeTo(165, 1e-6));
        expect(d.h, closeTo(82, 1e-6));
      },
    );

    test('selecting the same object is a no-op', () async {
      await startAndSettle();
      final before = channel.calls.length;
      vm.selectObject(MarkerArObject.chair);
      expect(channel.calls.length, before);
    });
  });

  group('calibration', () {
    test(
      'editing marker mm / trim forwards to the engine and persists',
      () async {
        await startAndSettle();
        await vm.setMarkerSizeMm(158.0);
        await vm.setScaleTrim(1.05);
        await vm.setCalibrationConfirmed(true);

        expect(channel.lastMarkerMm, 158.0);
        expect(channel.lastTrim, 1.05);
        expect(vm.isCalibrated, isTrue);

        final persisted = await MarkerCalibrationStore().load();
        expect(persisted.markerSizeMm, 158.0);
        expect(persisted.scaleTrim, 1.05);
        expect(persisted.confirmed, isTrue);
      },
    );

    test('resetCalibration returns to the uncalibrated defaults', () async {
      await startAndSettle();
      await vm.setMarkerSizeMm(180);
      await vm.setCalibrationConfirmed(true);
      await vm.resetCalibration();
      expect(vm.calibration, MarkerCalibration.initial);
      expect(vm.isCalibrated, isFalse);
    });

    test('the trim scales the reported real-world dimensions', () async {
      await startAndSettle();
      vm.selectObject(MarkerArObject.chair);
      await vm.setScaleTrim(1.10);
      final d = vm.currentDimensionsCm;
      expect(d.w, closeTo(77.0, 1e-6)); // 0.70 m × 100 × 1.10
    });
  });

  group('app lifecycle', () {
    test('setActive drives the native camera pause/resume', () async {
      await startAndSettle();
      vm.setActive(false);
      expect(channel.lastActive, isFalse);
      vm.setActive(true);
      expect(channel.lastActive, isTrue);
    });
  });

  group('selectable objects', () {
    test('exactly the four approved products — no QA cube', () async {
      await startAndSettle();
      expect(vm.selectableObjects, MarkerArObject.values);
      expect(vm.selectableObjects.length, 4);
      expect(vm.selectableObjects.map((o) => o.name).toList(), [
        'chair',
        'table',
        'lamp',
        'sofa',
      ]);
    });
  });

  group('R10 — Storage GLB delivery (debug surface)', () {
    test('is inert when no model service is attached', () async {
      await startAndSettle();
      expect(vm.r10Available, isFalse);
      await vm.r10Resolve(MarkerArObject.chair);
      expect(
        channel.calls.where((c) => c.startsWith('setExternalModel')),
        isEmpty,
      );
    });

    test(
      'a verified resolve installs the external file into the renderer',
      () async {
        final svc = _FakeModelService()
          ..outcome = RoomArModelReady(
            source: RoomArModelSource.freshDownload,
            file: File('/cache/room_ar_models/x/model.glb'),
          );
        final vm2 = MarkerArViewModel(channel: channel)
          ..attachModelService(svc);
        await vm2.start();

        expect(vm2.r10Available, isTrue);
        await vm2.r10Resolve(MarkerArObject.table);

        expect(svc.resolvedProductIds, ['glass-coffee-table']);
        expect(channel.lastExternalModel, isNotNull);
        expect(channel.lastExternalModel!.$1, MarkerArObject.table);
        expect(channel.lastExternalModel!.$2, contains('model.glb'));
        expect(
          vm2.r10ActiveSourceFor(MarkerArObject.table),
          RoomArModelSource.freshDownload,
        );
        vm2.dispose();
      },
    );

    test(
      'a rejected resolve falls back to the bundled asset (path = null)',
      () async {
        final svc = _FakeModelService()
          ..outcome = const RoomArModelIntegrityRejected('sha mismatch');
        final vm2 = MarkerArViewModel(channel: channel)
          ..attachModelService(svc);
        await vm2.start();

        await vm2.r10Resolve(MarkerArObject.sofa);

        expect(channel.lastExternalModel!.$1, MarkerArObject.sofa);
        expect(channel.lastExternalModel!.$2, isNull); // bundled fallback
        expect(
          vm2.r10ActiveSourceFor(MarkerArObject.sofa),
          RoomArModelSource.bundledFallback,
        );
        expect(vm2.r10HistoryFor(MarkerArObject.sofa), isNotEmpty);
        vm2.dispose();
      },
    );

    test('r10UseBundledModel tells the renderer to use the bundled asset, '
        'without touching the cache', () async {
      final svc = _FakeModelService()
        ..outcome = RoomArModelReady(
          source: RoomArModelSource.verifiedCache,
          file: File('/cache/model.glb'),
        );
      final vm2 = MarkerArViewModel(channel: channel)..attachModelService(svc);
      await vm2.start();
      await vm2.r10Resolve(MarkerArObject.chair);
      await vm2.r10UseBundledModel(MarkerArObject.chair);

      expect(channel.lastExternalModel, (MarkerArObject.chair, null));
      expect(vm2.r10ActiveSourceFor(MarkerArObject.chair), isNull);
      expect(svc.evictedProductIds, isEmpty); // cache untouched
      vm2.dispose();
    });

    test(
      'r10EvictCache evicts the exact entry for that product only',
      () async {
        final svc = _FakeModelService()
          ..outcome = RoomArModelReady(
            source: RoomArModelSource.verifiedCache,
            file: File('/cache/model.glb'),
          );
        final vm2 = MarkerArViewModel(channel: channel)
          ..attachModelService(svc);
        await vm2.start();

        await vm2.r10EvictCache(MarkerArObject.lamp);

        expect(svc.evictedProductIds, ['modern-table-lamp']);
        expect(
          vm2.r10HistoryFor(MarkerArObject.lamp).last,
          contains('evicted'),
        );
        vm2.dispose();
      },
    );
  });

  group('debug metrics HUD', () {
    test('is kDebugMode-gated and independently toggleable', () async {
      await startAndSettle();
      // tests run in debug mode
      expect(vm.debugAvailable, isTrue);
      expect(vm.debugHudVisible, isFalse);
      vm.toggleDebugHud();
      expect(vm.debugHudVisible, isTrue);
      vm.toggleDebugHud();
      expect(vm.debugHudVisible, isFalse);
    });
  });

  group('customer single-product mode (R15/R17)', () {
    final chairMeta = RoomArProductManifest.byProductId['luna-accent-chair']!;

    MarkerArViewModel customerVm({
      RoomArModelService? service,
      MarkerArObject object = MarkerArObject.table,
    }) => MarkerArViewModel(
      channel: channel,
      calibrationStore: MarkerCalibrationStore(),
      mode: MarkerArLaunchMode.customerProduct,
      initialObject: object,
      customerMetadata: object == MarkerArObject.chair ? chairMeta : null,
      roomArModelService: service,
    );

    test('hides the selector and every developer control', () async {
      final c = customerVm();
      await c.start();
      expect(c.isCustomerMode, isTrue);
      expect(c.selectableObjects, [MarkerArObject.table]);
      expect(c.debugAvailable, isFalse); // even though tests run in debug
      expect(c.debugHudVisible, isFalse);
      expect(c.r10Available, isFalse);
      c.toggleDebugHud();
      expect(c.debugHudVisible, isFalse); // inert
      c.dispose();
    });

    test('resolves the product GLB on start and hands the file to the '
        'renderer', () async {
      final svc = _FakeModelService()
        ..outcome = RoomArModelReady(
          source: RoomArModelSource.verifiedCache,
          file: File('/cache/room_ar_models/x/model.glb'),
        );
      final c = customerVm(service: svc, object: MarkerArObject.sofa);
      await c.start();
      await Future<void>.delayed(Duration.zero);

      expect(svc.resolvedProductIds, ['luna-3-seater-sofa']);
      expect(channel.lastExternalModel!.$1, MarkerArObject.sofa);
      expect(channel.lastExternalModel!.$2, contains('model.glb'));
      expect(c.deliverySource, RoomArModelSource.verifiedCache);
      c.dispose();
    });

    test('a delivery failure silently falls back to the bundled GLB', () async {
      final svc = _FakeModelService()..outcome = const RoomArModelOffline();
      final c = customerVm(service: svc, object: MarkerArObject.lamp);
      await c.start();
      await Future<void>.delayed(Duration.zero);

      expect(channel.lastExternalModel, (MarkerArObject.lamp, null));
      expect(c.deliverySource, RoomArModelSource.bundledFallback);
      expect(c.flash, contains('built-in'));
      c.dispose();
    });

    test(
      'with no model service the engine still runs on the bundled GLB',
      () async {
        final c = customerVm(object: MarkerArObject.chair);
        await c.start();
        await Future<void>.delayed(Duration.zero);
        expect(
          channel.calls.where((x) => x.startsWith('setExternalModel')),
          isEmpty,
        );
        expect(c.hasEngineError, isFalse);
        c.dispose();
      },
    );

    test('a service attached after construction still resolves once', () async {
      final svc = _FakeModelService()
        ..outcome = RoomArModelReady(
          source: RoomArModelSource.freshDownload,
          file: File('/cache/model.glb'),
        );
      final c = customerVm(object: MarkerArObject.table);
      await c.start();
      c.attachModelService(svc);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      expect(svc.resolvedProductIds, ['glass-coffee-table']);
      c.dispose();
    });

    test('dispose releases the native camera', () async {
      final c = customerVm();
      await c.start();
      c.dispose();
      expect(channel.lastActive, isFalse);
    });
  });
}
