import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart' show Offset, Size;
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/features/room_ar/marker_ar/models/marker_ar_object.dart';
import 'package:twin_ar/features/room_ar/marker_ar/room_ar_session_args.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_service.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_state.dart';
import 'package:twin_ar/features/room_ar/tier1_arcore/models/room_arcore_frame.dart';
import 'package:twin_ar/features/room_ar/tier1_arcore/services/room_arcore_channel.dart';
import 'package:twin_ar/features/room_ar/tier1_arcore/viewmodels/room_arcore_viewmodel.dart';

class _FakeChannel implements RoomArCoreChannel {
  final _events = StreamController<RoomArCoreFrame>.broadcast();
  final List<String> calls = [];
  (String, String?)? lastModel;
  bool? lastActive;

  void emit(RoomArCoreFrame f) => _events.add(f);

  @override
  Stream<RoomArCoreFrame> frames() => _events.stream;

  @override
  Future<void> setObject(String mode) async => calls.add('setObject:$mode');

  @override
  Future<void> setExternalModel(String mode, String? absolutePath) async {
    calls.add('setExternalModel:$mode:${absolutePath ?? 'null'}');
    lastModel = (mode, absolutePath);
  }

  @override
  Future<void> placeAt(double fx, double fy) async =>
      calls.add('placeAt:${fx.toStringAsFixed(3)},${fy.toStringAsFixed(3)}');

  @override
  Future<void> beginReposition() async => calls.add('beginReposition');

  @override
  Future<void> repositionTo(double fx, double fy) async => calls.add(
    'repositionTo:${fx.toStringAsFixed(3)},${fy.toStringAsFixed(3)}',
  );

  @override
  Future<void> endReposition() async => calls.add('endReposition');

  @override
  Future<void> setYaw(double degrees) async =>
      calls.add('setYaw:${degrees.toStringAsFixed(1)}');

  @override
  Future<void> resetPlacement() async => calls.add('resetPlacement');

  @override
  Future<void> setActive(bool active) async {
    calls.add('setActive:$active');
    lastActive = active;
  }

  Future<void> close() => _events.close();
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

RoomArSessionArgs argsFor(MarkerArObject o, ProductArMetadata metadata) =>
    RoomArSessionArgs(
      firestoreProductId: o.firestoreProductId,
      object: o,
      metadata: metadata,
      productTitle: o.displayName,
    );

RoomArSessionArgs genericArgs(String productId, String title) =>
    RoomArSessionArgs(
      firestoreProductId: productId,
      object: null,
      metadata: ProductArMetadata(
        storagePath: 'products/$productId/ar/model-v1.glb',
        modelVersion: '1',
        sha256: 'a' * 64,
        widthM: 0.5,
        depthM: 0.5,
        heightM: 0.5,
      ),
      productTitle: title,
    );

final _chairMeta = ProductArMetadata(
  storagePath: 'products/luna-accent-chair/ar/model-v1.glb',
  modelVersion: '1',
  sha256: 'b' * 64,
  widthM: 0.7,
  depthM: 0.72,
  heightM: 0.82,
);

void main() {
  late _FakeChannel channel;

  setUp(() => channel = _FakeChannel());
  tearDown(() => channel.close());

  RoomArCoreViewModel vmFor(
    RoomArSessionArgs args, {
    RoomArModelService? service,
  }) =>
      RoomArCoreViewModel(args: args, channel: channel, modelService: service);

  group('startup', () {
    test('sets the native object and shows the bundled model immediately for '
        'one of the four originally-approved products', () async {
      final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
      await vm.start();
      expect(channel.calls, contains('setObject:chair'));
      expect(channel.lastModel, ('chair', null));
    });

    test(
      'a generic (coverage-expansion / future Admin) product waits for '
      'the verified file — never flashes an unrelated bundled model',
      () async {
        final vm = vmFor(
          genericArgs('future-admin-product-99', 'A New Product'),
        );
        await vm.start();
        expect(channel.calls, contains('setObject:future-admin-product-99'));
        expect(
          channel.calls.any((c) => c.startsWith('setExternalModel')),
          isFalse,
        );
      },
    );
  });

  group('model resolution (reuses the same RoomArModelService contract as '
      'Tier 2/3)', () {
    test(
      'a verified resolve installs the exact file for this product',
      () async {
        final svc = _FakeModelService()
          ..outcome = RoomArModelReady(
            source: RoomArModelSource.verifiedCache,
            file: File('/cache/room_ar_models/x/model.glb'),
          );
        final vm = vmFor(
          argsFor(MarkerArObject.sofa, _chairMeta),
          service: svc,
        );
        await vm.start();
        await Future<void>.delayed(Duration.zero);

        expect(svc.resolved, ['luna-3-seater-sofa']);
        expect(channel.lastModel!.$1, 'sofa');
        expect(channel.lastModel!.$2, contains('model.glb'));
        expect(vm.deliverySource, RoomArModelSource.verifiedCache);
      },
    );

    test('offline with a bundled fallback keeps the bundled model and says '
        'so honestly', () async {
      final svc = _FakeModelService()..outcome = const RoomArModelOffline();
      final vm = vmFor(argsFor(MarkerArObject.lamp, _chairMeta), service: svc);
      await vm.start();
      await Future<void>.delayed(Duration.zero);

      expect(channel.lastModel, ('lamp', null));
      expect(vm.deliverySource, RoomArModelSource.bundledFallback);
      expect(vm.flash, contains('built-in'));
    });

    test('a resolve failure with no bundled fallback surfaces the honest '
        'unavailable state — never substitutes a model', () async {
      final svc = _FakeModelService()..outcome = const RoomArModelOffline();
      final vm = vmFor(
        genericArgs('beige-ar-in-stock-5', 'Beige AR Rug 5'),
        service: svc,
      );
      await vm.start();
      await Future<void>.delayed(Duration.zero);

      expect(vm.customerModelUnavailable, isTrue);
      expect(
        channel.calls.any((c) => c.startsWith('setExternalModel')),
        isFalse,
      );
    });

    test('non-renderable metadata (should never happen past the prep-screen '
        'gate) never even attempts a fetch', () async {
      final svc = _FakeModelService();
      final vm = RoomArCoreViewModel(
        args: RoomArSessionArgs(
          firestoreProductId: 'future-admin-product-99',
          object: null,
          metadata: const ProductArMetadata(
            storagePath: 'products/future-admin-product-99/ar/model-v1.glb',
            modelVersion: '', // malformed — not renderable
            sha256: 'not-a-hash',
            widthM: 0,
            depthM: 0,
            heightM: 0,
          ),
          productTitle: 'A New Product',
        ),
        channel: channel,
        modelService: svc,
      );
      await vm.start();
      await Future<void>.delayed(Duration.zero);
      expect(svc.resolved, isEmpty);
      expect(vm.customerModelUnavailable, isTrue);
    });

    test('service attached after start still resolves exactly once', () async {
      final svc = _FakeModelService()
        ..outcome = RoomArModelReady(
          source: RoomArModelSource.freshDownload,
          file: File('/cache/m.glb'),
        );
      final vm = vmFor(argsFor(MarkerArObject.table, _chairMeta));
      await vm.start();
      vm.attachModelService(svc);
      await Future<void>.delayed(Duration.zero);
      vm.attachModelService(svc); // idempotent
      await Future<void>.delayed(Duration.zero);
      expect(svc.resolved, ['glass-coffee-table']);
    });

    test('onPlatformViewReady re-sends setObject and, once a Storage-delivered '
        'external model has resolved, re-sends its exact file path too — the '
        'guaranteed-post-creation defence against a `setExternalModel` channel '
        'call racing the PlatformView\'s own creation (the coverage-expansion '
        '/ future-Admin product path, which — unlike the four bundled '
        'products — has no creation-param fallback since the file is only '
        'known after an async download/cache resolve)', () async {
      final svc = _FakeModelService()
        ..outcome = RoomArModelReady(
          source: RoomArModelSource.verifiedCache,
          file: File('/cache/room_ar_models/x/rug.glb'),
        );
      final vm = vmFor(
        genericArgs('beige-ar-in-stock-5', 'Beige AR Rug 5'),
        service: svc,
      );
      await vm.start();
      await Future<void>.delayed(Duration.zero);
      channel.calls.clear();

      vm.onPlatformViewReady();

      expect(channel.calls, contains('setObject:beige-ar-in-stock-5'));
      expect(
        channel.calls,
        contains(
          'setExternalModel:beige-ar-in-stock-5:/cache/room_ar_models/x/rug.glb',
        ),
      );
    });

    test('onPlatformViewReady is a safe no-op re-send for a bundled product '
        'before any external model has resolved — it never sends a null path '
        'and drops an already-showing bundled model', () async {
      final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
      await vm.start();
      channel.calls.clear();

      vm.onPlatformViewReady();

      expect(channel.calls, ['setObject:chair']);
      expect(
        channel.calls.any((c) => c.startsWith('setExternalModel')),
        isFalse,
      );
    });
  });

  group('frame state → guidance / eligibility', () {
    test(
      'tracking + plane found + not placed → ready-to-place guidance',
      () async {
        final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
        await vm.start();
        channel.emit(
          const RoomArCoreFrame(
            tracking: true,
            trackingFailureReason: 'NONE',
            planesFound: true,
            hasAnchor: false,
            anchorTracking: false,
            justPlaced: false,
            reticleVisible: true,
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(vm.tracking, isTrue);
        expect(vm.planesFound, isTrue);
        expect(vm.hasAnchor, isFalse);
        expect(vm.guidanceMessage, contains('Tap'));
        expect(vm.hasEngineError, isFalse);
      },
    );

    test(
      'a terminal native state surfaces as an honest engine error',
      () async {
        final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
        await vm.start();
        channel.emit(
          const RoomArCoreFrame(
            tracking: false,
            trackingFailureReason: 'NONE',
            planesFound: false,
            hasAnchor: false,
            anchorTracking: false,
            justPlaced: false,
            reticleVisible: false,
            terminalState: 'arcore-unavailable',
            error: 'This device does not support AR',
          ),
        );
        await Future<void>.delayed(Duration.zero);
        expect(vm.hasEngineError, isTrue);
        expect(vm.engineErrorMessage, 'This device does not support AR');
      },
    );

    test('a rejected initial-placement tap surfaces as honest visible '
        'feedback, not silence (tracker §32)', () async {
      final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
      await vm.start();
      channel.emit(
        const RoomArCoreFrame(
          tracking: true,
          trackingFailureReason: 'NONE',
          planesFound: true,
          hasAnchor: false,
          anchorTracking: false,
          justPlaced: false,
          reticleVisible: true,
          tapRejected: true,
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(vm.flash, isNotNull);
      expect(vm.flash, contains("Couldn't find a surface"));
    });
  });

  group('placement gestures (normalized, device-pixel-ratio independent)', () {
    test(
      'placeAt forwards a normalized fraction of the surface size',
      () async {
        final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
        await vm.start();
        vm.setSurfaceSize(const Size(1000, 2000));
        vm.placeAt(const Offset(500, 1000));
        expect(channel.calls, contains('placeAt:0.500,0.500'));
      },
    );

    test('placeAt is a no-op before the surface size is known', () async {
      final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
      await vm.start();
      vm.placeAt(const Offset(10, 10));
      expect(channel.calls.any((c) => c.startsWith('placeAt')), isFalse);
    });

    test('dragTo/beginDrag/endDrag only forward once something is placed — '
        'nothing to drag before that', () async {
      final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
      await vm.start();
      vm.setSurfaceSize(const Size(1000, 1000));

      vm.beginDrag();
      vm.dragTo(const Offset(100, 100));
      vm.endDrag();
      expect(channel.calls, isNot(contains('beginReposition')));
      expect(channel.calls.any((c) => c.startsWith('repositionTo')), isFalse);
      expect(channel.calls, isNot(contains('endReposition')));

      channel.emit(
        const RoomArCoreFrame(
          tracking: true,
          trackingFailureReason: 'NONE',
          planesFound: true,
          hasAnchor: true,
          anchorTracking: true,
          justPlaced: true,
          reticleVisible: false,
        ),
      );
      await Future<void>.delayed(Duration.zero);

      vm.beginDrag();
      vm.dragTo(const Offset(250, 500));
      vm.endDrag();
      expect(channel.calls, contains('beginReposition'));
      expect(channel.calls, contains('repositionTo:0.250,0.500'));
      expect(channel.calls, contains('endReposition'));
    });

    test(
      'rotateTo forwards degrees, wrapped to +/-pi radians internally',
      () async {
        final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
        await vm.start();
        vm.rotateTo(3.14159265 / 2); // 90 degrees
        expect(channel.calls.last, startsWith('setYaw:90.0'));
      },
    );

    test(
      'resetPlacement clears yaw and forwards to the native layer',
      () async {
        final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
        await vm.start();
        vm.rotateTo(1.0);
        vm.resetPlacement();
        expect(channel.calls, contains('resetPlacement'));
        expect(vm.yawAtGestureStart, 0.0);
      },
    );
  });

  group('lifecycle + fallback', () {
    test(
      'fallbackPreviewArgs is always the same eligible session args — the '
      '"prefer a 3D preview" link never needs a separate eligibility check',
      () async {
        final args = argsFor(MarkerArObject.chair, _chairMeta);
        final vm = vmFor(args);
        expect(vm.fallbackPreviewArgs, same(args));
      },
    );

    test('setActive drives the native session pause/resume', () async {
      final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
      await vm.start();
      vm.setActive(false);
      expect(channel.lastActive, isFalse);
      vm.setActive(true);
      expect(channel.lastActive, isTrue);
    });

    test('dispose releases the native session', () async {
      final vm = vmFor(argsFor(MarkerArObject.chair, _chairMeta));
      await vm.start();
      vm.dispose();
      expect(channel.lastActive, isFalse);
    });
  });
}
