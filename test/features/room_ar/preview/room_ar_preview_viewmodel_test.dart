import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/marker_ar/room_ar_session_args.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_service.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_state.dart';
import 'package:twin_ar/features/room_ar/preview/room_ar_preview_channel.dart';
import 'package:twin_ar/features/room_ar/preview/room_ar_preview_viewmodel.dart';
import 'package:twin_ar/features/room_ar/room_ar_product_manifest.dart';

class _FakeChannel implements RoomArPreviewChannel {
  final _load = StreamController<RoomArPreviewLoad>.broadcast();
  final List<String> calls = [];
  (String, String?)? lastModel;
  bool? lastActive;

  void emit(RoomArPreviewLoad s) => _load.add(s);

  @override
  Stream<RoomArPreviewLoad> loadStates() => _load.stream;

  @override
  Future<void> setModel(String mode, String? verifiedPath) async {
    calls.add('setModel:$mode:${verifiedPath ?? 'null'}');
    lastModel = (mode, verifiedPath);
  }

  @override
  Future<void> orbit(double dx, double dy) async => calls.add('orbit:$dx,$dy');
  @override
  Future<void> pan(double dx, double dy) async => calls.add('pan:$dx,$dy');
  @override
  Future<void> zoom(double scale) async => calls.add('zoom:$scale');
  @override
  Future<void> resetView() async => calls.add('reset');
  @override
  Future<void> setActive(bool active) async {
    calls.add('setActive:$active');
    lastActive = active;
  }

  Future<void> close() => _load.close();
}

class _FakeModelService implements RoomArModelService {
  RoomArModelState outcome = const RoomArModelOffline();
  final List<String> resolved = [];

  @override
  Future<RoomArModelState> resolve({
    required String productId,
    required ProductArMetadata metadata,
    void Function(RoomArModelState state)? onState,
  }) async {
    resolved.add(productId);
    onState?.call(const RoomArModelDownloading());
    onState?.call(outcome);
    return outcome;
  }

  @override
  Future<RoomArModelReady?> cachedOnly({
    required String productId,
    required ProductArMetadata metadata,
  }) async => null;

  @override
  Future<void> evictCachedEntry({
    required String productId,
    required ProductArMetadata metadata,
  }) async {}
}

RoomArSessionArgs argsFor(MarkerArObject o) => RoomArSessionArgs(
  object: o,
  metadata: RoomArProductManifest.byProductId[o.firestoreProductId]!,
  productTitle: o.displayName,
);

void main() {
  late _FakeChannel channel;

  setUp(() => channel = _FakeChannel());
  tearDown(() => channel.close());

  RoomArPreviewViewModel vmFor(
    MarkerArObject o, {
    RoomArModelService? service,
  }) => RoomArPreviewViewModel(
    args: argsFor(o),
    channel: channel,
    modelService: service,
  );

  test(
    'renders only the opened product; shows the bundled model immediately',
    () async {
      final vm = vmFor(MarkerArObject.sofa);
      await vm.start();
      expect(vm.object, MarkerArObject.sofa);
      expect(vm.productTitle, 'Luna Right-Chaise Sectional Sofa');
      // bundled model handed over first (path == null)
      expect(channel.lastModel, ('sofa', null));
      vm.dispose();
    },
  );

  test('a verified resolve swaps in the Storage-delivered file', () async {
    final svc = _FakeModelService()
      ..outcome = RoomArModelReady(
        source: RoomArModelSource.verifiedCache,
        file: File('/cache/room_ar_models/x/model.glb'),
      );
    final vm = vmFor(MarkerArObject.chair, service: svc);
    await vm.start();
    await Future<void>.delayed(Duration.zero);

    expect(svc.resolved, ['luna-accent-chair']);
    expect(channel.lastModel!.$2, contains('model.glb'));
    expect(vm.deliverySource, RoomArModelSource.verifiedCache);
    vm.dispose();
  });

  test(
    'offline delivery keeps the bundled model and says so honestly',
    () async {
      final svc = _FakeModelService()..outcome = const RoomArModelOffline();
      final vm = vmFor(MarkerArObject.lamp, service: svc);
      await vm.start();
      await Future<void>.delayed(Duration.zero);

      expect(channel.lastModel, ('lamp', null));
      expect(vm.deliverySource, RoomArModelSource.bundledFallback);
      expect(vm.notice, contains('offline'));
      expect(vm.renderFailed, isFalse);
      vm.dispose();
    },
  );

  test(
    'a native "failed" load state surfaces the honest render-failed screen',
    () async {
      final vm = vmFor(MarkerArObject.table);
      await vm.start();
      channel.emit(RoomArPreviewLoad.failed);
      await Future<void>.delayed(Duration.zero);
      expect(vm.renderFailed, isTrue);
      vm.dispose();
    },
  );

  test('gestures forward to the native orbit renderer', () async {
    final vm = vmFor(MarkerArObject.chair);
    await vm.start();
    vm.orbit(4, -2);
    vm.pan(1, 1);
    vm.zoom(1.2);
    vm.resetView();
    expect(
      channel.calls,
      containsAll(['orbit:4.0,-2.0', 'pan:1.0,1.0', 'zoom:1.2', 'reset']),
    );
    vm.dispose();
  });

  test(
    'lifecycle: setActive drives the renderer; dispose releases it',
    () async {
      final vm = vmFor(MarkerArObject.chair);
      await vm.start();
      vm.setActive(false);
      expect(channel.lastActive, isFalse);
      vm.setActive(true);
      expect(channel.lastActive, isTrue);
      vm.dispose();
      expect(channel.lastActive, isFalse); // dispose forces inactive
    },
  );

  test('service attached after start still resolves exactly once', () async {
    final svc = _FakeModelService()
      ..outcome = RoomArModelReady(
        source: RoomArModelSource.freshDownload,
        file: File('/cache/m.glb'),
      );
    final vm = vmFor(MarkerArObject.table);
    await vm.start();
    vm.attachModelService(svc);
    await Future<void>.delayed(Duration.zero);
    vm.attachModelService(svc); // idempotent
    await Future<void>.delayed(Duration.zero);
    expect(svc.resolved, ['glass-coffee-table']);
    vm.dispose();
  });
}
