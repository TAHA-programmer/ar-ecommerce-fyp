import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/admin/ar_media_management/viewmodels/admin_ar_model_preview_viewmodel.dart';
import 'package:twin_ar/features/room_ar/preview/room_ar_preview_channel.dart';

import 'ar_glb_test_support.dart';

class _FakeChannel implements RoomArPreviewChannel {
  final _load = StreamController<RoomArPreviewLoad>.broadcast();
  (String, String?)? lastModel;
  final List<String> calls = [];

  void emit(RoomArPreviewLoad s) => _load.add(s);

  @override
  Stream<RoomArPreviewLoad> loadStates() => _load.stream;
  @override
  Future<void> setModel(String mode, String? path) async {
    lastModel = (mode, path);
    calls.add('setModel:$mode');
  }

  @override
  Future<void> orbit(double dx, double dy) async {}
  @override
  Future<void> pan(double dx, double dy) async {}
  @override
  Future<void> zoom(double s) async {}
  @override
  Future<void> resetView() async {}
  @override
  Future<void> setActive(bool a) async => calls.add('setActive:$a');
}

void main() {
  late Directory tmp;
  late MockStorageService storage;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('admin_preview_vm');
    storage = MockStorageService();
  });
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test(
    'a staged local file resolves to itself and is NOT sent via a racing '
    'setModel on start (creation-param path); onRendererCreated re-sends it',
    () async {
      final glb = writeBoxGlb(dir: tmp, name: 'staged.glb');
      final channel = _FakeChannel();
      final vm = AdminArModelPreviewViewModel(
        args: AdminArModelPreviewArgs(
          localFilePath: glb.path,
          productTitle: 'Chair',
          widthM: 0.7,
          depthM: 0.72,
          heightM: 0.82,
        ),
        channel: channel,
        storage: storage,
      );
      addTearDown(vm.dispose);

      await vm.start();
      // The View builds the PlatformView with this as a creation param — no
      // dropped-setModel race, no setModel call on start at all.
      expect(vm.resolvedFilePath, glb.path);
      expect(channel.calls.where((c) => c.startsWith('setModel')), isEmpty);
      expect(vm.renderFailed, isFalse);
      // Still "preparing" until the native renderer reports ready.
      expect(vm.isPreparing, isTrue);
      channel.emit(RoomArPreviewLoad.ready);
      await Future<void>.delayed(Duration.zero);
      expect(vm.isPreparing, isFalse);

      // The guaranteed-post-creation belt-and-braces re-send.
      vm.onRendererCreated();
      expect(channel.lastModel, ('admin', glb.path));
    },
  );

  test(
    'a committed model is downloaded, re-verified and resolved to a temp file',
    () async {
      final bytes = writeBoxGlb(
        dir: tmp,
        name: 'committed.glb',
      ).readAsBytesSync();
      const path = 'products/velvet-armchair/ar/model-v1.glb';
      storage.arModelBytesByPath[path] = bytes;

      final channel = _FakeChannel();
      final vm = AdminArModelPreviewViewModel(
        args: const AdminArModelPreviewArgs(
          metadata: ProductArMetadata(
            storagePath: path,
            modelVersion: '1',
            sha256: 'ignored-by-inspector',
            widthM: 0.7,
            depthM: 0.72,
            heightM: 0.82,
          ),
          productTitle: 'Armchair',
          widthM: 0.7,
          depthM: 0.72,
          heightM: 0.82,
        ),
        channel: channel,
        storage: storage,
        tempDirectory: tmp,
      );
      addTearDown(vm.dispose);

      await vm.start();
      expect(vm.resolvedFilePath, contains('admin_ar_preview_'));
      expect(File(vm.resolvedFilePath!).existsSync(), isTrue);
      expect(vm.renderFailed, isFalse);

      vm.onRendererCreated();
      expect(channel.lastModel!.$1, 'admin');
      expect(channel.lastModel!.$2, vm.resolvedFilePath);
    },
  );

  test('a Storage read failure surfaces an honest failure state', () async {
    storage.failDownloadArModelWith = Exception('permission denied');
    final channel = _FakeChannel();
    final vm = AdminArModelPreviewViewModel(
      args: AdminArModelPreviewArgs(
        metadata: ProductArMetadata(
          storagePath: 'products/x/ar/model-v1.glb',
          modelVersion: '1',
          sha256: 'z' * 64,
          widthM: 1,
          depthM: 1,
          heightM: 1,
        ),
        productTitle: 'X',
        widthM: 1,
        depthM: 1,
        heightM: 1,
      ),
      channel: channel,
      storage: storage,
    );
    addTearDown(vm.dispose);

    await vm.start();
    expect(vm.renderFailed, isTrue);
    expect(vm.notice, isNotNull);
    expect(vm.resolvedFilePath, isNull);
  });
}
