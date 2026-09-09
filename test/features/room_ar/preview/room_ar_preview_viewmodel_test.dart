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
  final List<ProductArMetadata> resolvedMetadata = [];

  @override
  Future<RoomArModelState> resolve({
    required String productId,
    required ProductArMetadata metadata,
    void Function(RoomArModelState state)? onState,
  }) async {
    resolved.add(productId);
    resolvedMetadata.add(metadata);
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
  firestoreProductId: o.firestoreProductId,
  object: o,
  metadata: RoomArProductManifest.byProductId[o.firestoreProductId]!,
  productTitle: o.displayName,
);

/// A session for a product with no bundled/native-specialized rendering slot
/// — every Phase 9.2 coverage-expansion product, and any future Admin-created
/// one. `object` is deliberately null (see `RoomArSessionArgs`'s doc comment).
RoomArSessionArgs genericArgsFor(
  String productId,
  String title, {
  ProductArMetadata? metadata,
}) => RoomArSessionArgs(
  firestoreProductId: productId,
  object: null,
  metadata:
      metadata ??
      ProductArMetadata(
        storagePath: 'products/$productId/ar/model-v1.glb',
        modelVersion: '1',
        sha256: 'a' * 64,
        widthM: 0.5,
        depthM: 0.5,
        heightM: 0.5,
      ),
  productTitle: title,
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

  RoomArPreviewViewModel vmForArgs(
    RoomArSessionArgs args, {
    RoomArModelService? service,
  }) => RoomArPreviewViewModel(
    args: args,
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

  group('Phase 9.2 dynamic eligibility (no bundled fallback)', () {
    test('a generic product waits for the verified Storage file — never '
        'flashes an unrelated bundled model on start', () async {
      final vm = vmForArgs(
        genericArgsFor('future-admin-product-99', 'A Brand New Product'),
      );
      await vm.start();
      // Unlike the original-four path, nothing is sent to the native side
      // yet — there is no bundled asset to show while resolution is
      // pending, so it stays "loading" rather than briefly showing chair.
      expect(channel.lastModel, isNull);
      expect(vm.isPreparing, isTrue);
      vm.dispose();
    });

    test('a verified resolve installs this exact product\'s file, keyed by its '
        'own product id (never chair/table/lamp/sofa)', () async {
      final svc = _FakeModelService()
        ..outcome = RoomArModelReady(
          source: RoomArModelSource.verifiedCache,
          file: File('/cache/room_ar_models/x/armchair.glb'),
        );
      final vm = vmForArgs(
        genericArgsFor('future-admin-product-99', 'A Brand New Product'),
        service: svc,
      );
      await vm.start();
      await Future<void>.delayed(Duration.zero);

      expect(svc.resolved, ['future-admin-product-99']);
      expect(vm.nativeMode, 'future-admin-product-99');
      expect(channel.lastModel!.$1, 'future-admin-product-99');
      expect(channel.lastModel!.$2, contains('armchair.glb'));
      vm.dispose();
    });

    test(
      'a resolve failure with no bundled fallback surfaces the honest '
      'render-failed screen — never substitutes chair or any other model',
      () async {
        final svc = _FakeModelService()..outcome = const RoomArModelOffline();
        final vm = vmForArgs(
          genericArgsFor('future-admin-product-99', 'A Brand New Product'),
          service: svc,
        );
        await vm.start();
        await Future<void>.delayed(Duration.zero);

        // The viewmodel drives the native "failed" event itself (there is no
        // real bundled asset to fall back to) — never sends a bundled/null
        // path pretending it's a safe fallback for this product.
        expect(channel.lastModel, ('future-admin-product-99', null));
        channel.emit(RoomArPreviewLoad.failed);
        await Future<void>.delayed(Duration.zero);
        expect(vm.renderFailed, isTrue);
        expect(vm.deliverySource, isNot(RoomArModelSource.bundledFallback));
        vm.dispose();
      },
    );

    test(
      'non-renderable metadata (should never happen past the prep-screen '
      'gate) still triggers the honest failure path, not a substitute',
      () async {
        final svc = _FakeModelService();
        final vm = vmForArgs(
          genericArgsFor(
            'future-admin-product-99',
            'A Brand New Product',
            metadata: const ProductArMetadata(
              storagePath: 'products/future-admin-product-99/ar/model-v1.glb',
              modelVersion: '', // malformed — not renderable
              sha256: 'not-a-hash',
              widthM: 0,
              depthM: 0,
              heightM: 0,
            ),
          ),
          service: svc,
        );
        await vm.start();
        await Future<void>.delayed(Duration.zero);
        expect(svc.resolved, isEmpty); // never even attempted a fetch
        expect(channel.lastModel, ('future-admin-product-99', null));
        vm.dispose();
      },
    );

    test(
      'a product with a stale RoomArProductManifest entry resolves using its '
      'live Firestore metadata, never the frozen manifest values — matches '
      "Tier-2's (MarkerArViewModel) precedence, so a customer sees the exact "
      'model an Admin just replaced, on either tier',
      () async {
        // `luna-accent-chair` genuinely has a manifest entry — simulate an
        // Admin having replaced its model (new storage path / sha256 / dims)
        // after the manifest was hash-locked at authoring time.
        final replaced = ProductArMetadata(
          storagePath: 'products/luna-accent-chair/ar/model-v2.glb',
          modelVersion: '2',
          sha256: 'b' * 64,
          widthM: 0.75,
          depthM: 0.80,
          heightM: 0.90,
        );
        expect(
          replaced,
          isNot(RoomArProductManifest.byProductId['luna-accent-chair']),
        );
        final svc = _FakeModelService()
          ..outcome = RoomArModelReady(
            source: RoomArModelSource.verifiedCache,
            file: File('/cache/room_ar_models/x/model-v2.glb'),
          );
        final vm = vmForArgs(
          RoomArSessionArgs(
            firestoreProductId: 'luna-accent-chair',
            object: MarkerArObject.chair,
            metadata: replaced,
            productTitle: 'Luna Accent Chair',
          ),
          service: svc,
        );
        await vm.start();
        await Future<void>.delayed(Duration.zero);

        expect(svc.resolvedMetadata, [replaced]);
        vm.dispose();
      },
    );

    test('a shared-design product resolves by its own id, distinct from '
        'other members of its group', () async {
      final svc = _FakeModelService()
        ..outcome = RoomArModelReady(
          source: RoomArModelSource.verifiedCache,
          file: File('/cache/rug.glb'),
        );
      final vm = vmForArgs(
        genericArgsFor('beige-ar-in-stock-5', 'Beige AR Rug 5'),
        service: svc,
      );
      await vm.start();
      await Future<void>.delayed(Duration.zero);
      expect(svc.resolved, ['beige-ar-in-stock-5']);
      expect(svc.resolved, isNot(contains('beige-ar-in-stock-7')));
      vm.dispose();
    });
  });
}
