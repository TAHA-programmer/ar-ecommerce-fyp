import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_cache.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_service.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_state.dart';
import 'package:twin_ar/features/room_ar/model_delivery/room_ar_model_storage_source.dart';

import 'glb_test_support.dart';

/// Deterministic in-memory Storage stand-in. Records download attempts and lets
/// a test inject bytes, latency and failures.
class FakeStorageSource implements RoomArModelStorageSource {
  FakeStorageSource(this.bytes);

  Uint8List? bytes;
  RoomArModelStorageException? failWith;
  Duration latency = Duration.zero;

  /// When set, only this many leading bytes are actually written (simulates an
  /// interrupted / truncated transfer that still "completes").
  int? truncateTo;

  int downloadCount = 0;

  @override
  Future<int?> sizeOf(String storagePath) async => bytes?.length;

  @override
  Future<void> downloadTo(
    String storagePath,
    File destination, {
    int? maxBytes,
    void Function(int received, int? total)? onProgress,
  }) async {
    downloadCount++;
    if (latency > Duration.zero) await Future<void>.delayed(latency);
    if (failWith != null) throw failWith!;
    final b = bytes!;
    if (maxBytes != null && b.length > maxBytes) {
      throw const RoomArModelStorageException(
        RoomArModelStorageErrorKind.tooLarge,
        'too large',
      );
    }
    final payload = truncateTo == null
        ? b
        : Uint8List.sublistView(b, 0, truncateTo!.clamp(0, b.length));
    onProgress?.call(payload.length, b.length);
    await destination.writeAsBytes(payload, flush: true);
  }
}

ProductArMetadata metaFor(
  Uint8List glb, {
  String path = 'products/luna-accent-chair/ar/model-v1.glb',
  String version = '1',
  double w = 0.70,
  double d = 0.72,
  double h = 0.82,
}) => ProductArMetadata(
  storagePath: path,
  modelVersion: version,
  sha256: sha256.convert(glb).toString(),
  widthM: w,
  depthM: d,
  heightM: h,
);

void main() {
  late Directory tempRoot;
  late RoomArModelCache cache;
  final chairGlb = buildGlb(
    boxGltf(x: 0.70, y: 0.82, z: 0.72),
    bin: Uint8List(16),
  );

  setUp(() async {
    tempRoot = await Directory.systemTemp.createTemp('room_ar_model_test');
    cache = RoomArModelCache(tempRoot);
  });
  tearDown(() async {
    // The service fire-and-forgets a last-known-good refresh; on Windows a
    // just-closed handle can briefly keep the temp tree locked. Best-effort.
    for (var attempt = 0; attempt < 3; attempt++) {
      try {
        if (await tempRoot.exists()) await tempRoot.delete(recursive: true);
        return;
      } catch (_) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
      }
    }
  });

  DefaultRoomArModelService serviceWith(FakeStorageSource storage) =>
      DefaultRoomArModelService(storageSource: storage, modelCache: cache);

  test('downloads, verifies and promotes a valid model', () async {
    final storage = FakeStorageSource(chairGlb);
    final meta = metaFor(chairGlb);
    final states = <RoomArModelState>[];

    final result = await serviceWith(storage).resolve(
      productId: 'luna-accent-chair',
      metadata: meta,
      onState: states.add,
    );

    expect(result, isA<RoomArModelReady>());
    final ready = result as RoomArModelReady;
    expect(ready.source, RoomArModelSource.freshDownload);
    expect(await ready.file!.exists(), isTrue);
    expect(ready.file!.path, contains('model.glb'));
    expect(ready.file!.path, isNot(contains('.tmp')));
    // structural + downloading + verifying transitions were surfaced
    expect(states.any((s) => s is RoomArModelDownloading), isTrue);
    expect(states.any((s) => s is RoomArModelVerifying), isTrue);
    // .tmp swept
    final tmp = Directory('${tempRoot.path}/.tmp');
    if (await tmp.exists()) {
      expect(await tmp.list().isEmpty, isTrue);
    }
  });

  test(
    'a second resolve is served from the verified cache (no network)',
    () async {
      final storage = FakeStorageSource(chairGlb);
      final meta = metaFor(chairGlb);
      await serviceWith(
        storage,
      ).resolve(productId: 'luna-accent-chair', metadata: meta);
      expect(storage.downloadCount, 1);

      final again = await serviceWith(
        storage,
      ).resolve(productId: 'luna-accent-chair', metadata: meta);
      expect(storage.downloadCount, 1);
      expect(
        (again as RoomArModelReady).source,
        RoomArModelSource.verifiedCache,
      );
    },
  );

  test('deduplicates concurrent requests for the same model', () async {
    final storage = FakeStorageSource(chairGlb)
      ..latency = const Duration(milliseconds: 80);
    final meta = metaFor(chairGlb);
    final service = serviceWith(storage);

    final results = await Future.wait([
      service.resolve(productId: 'luna-accent-chair', metadata: meta),
      service.resolve(productId: 'luna-accent-chair', metadata: meta),
      service.resolve(productId: 'luna-accent-chair', metadata: meta),
    ]);

    expect(storage.downloadCount, 1);
    expect(results.every((r) => r is RoomArModelReady), isTrue);
  });

  test('offline with no cache → RoomArModelOffline', () async {
    final storage = FakeStorageSource(chairGlb)
      ..failWith = const RoomArModelStorageException(
        RoomArModelStorageErrorKind.offline,
        'no network',
      );
    final result = await serviceWith(
      storage,
    ).resolve(productId: 'luna-accent-chair', metadata: metaFor(chairGlb));
    expect(result, isA<RoomArModelOffline>());
  });

  test('offline after a prior success → last-known-good is served', () async {
    final storage = FakeStorageSource(chairGlb);
    final v1 = metaFor(chairGlb, version: '1');
    await serviceWith(
      storage,
    ).resolve(productId: 'luna-accent-chair', metadata: v1);

    // a new version, but the network is down
    final v2Glb = buildGlb(
      boxGltf(x: 0.70, y: 0.82, z: 0.72),
      bin: Uint8List(32),
    );
    final v2 = metaFor(
      v2Glb,
      version: '2',
      path: 'products/luna-accent-chair/ar/model-v2.glb',
    );
    final offlineStorage = FakeStorageSource(v2Glb)
      ..failWith = const RoomArModelStorageException(
        RoomArModelStorageErrorKind.offline,
        'no network',
      );
    final result = await serviceWith(
      offlineStorage,
    ).resolve(productId: 'luna-accent-chair', metadata: v2);
    expect(result, isA<RoomArModelReady>());
    expect(
      (result as RoomArModelReady).source,
      RoomArModelSource.lastKnownGood,
    );
  });

  test(
    'an interrupted / truncated download is rejected, not promoted',
    () async {
      final storage = FakeStorageSource(chairGlb)
        ..truncateTo = chairGlb.length - 40;
      final result = await serviceWith(
        storage,
      ).resolve(productId: 'luna-accent-chair', metadata: metaFor(chairGlb));
      expect(result, isA<RoomArModelIntegrityRejected>());
      // nothing promoted
      final entries = tempRoot
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('model.glb'));
      expect(entries, isEmpty);
    },
  );

  test('a SHA-256 mismatch is rejected', () async {
    final storage = FakeStorageSource(chairGlb);
    // declare the wrong hash
    final meta = ProductArMetadata(
      storagePath: 'products/luna-accent-chair/ar/model-v1.glb',
      modelVersion: '1',
      sha256:
          '0000000000000000000000000000000000000000000000000000000000000000',
      widthM: 0.70,
      depthM: 0.72,
      heightM: 0.82,
    );
    final result = await serviceWith(
      storage,
    ).resolve(productId: 'luna-accent-chair', metadata: meta);
    expect(result, isA<RoomArModelIntegrityRejected>());
    expect(
      (result as RoomArModelIntegrityRejected).reason,
      contains('checksum'),
    );
  });

  test('a bounding-box mismatch is rejected', () async {
    final storage = FakeStorageSource(chairGlb);
    final meta = metaFor(chairGlb, w: 2.0, d: 2.0, h: 2.0);
    final result = await serviceWith(
      storage,
    ).resolve(productId: 'luna-accent-chair', metadata: meta);
    expect(result, isA<RoomArModelIntegrityRejected>());
    expect(
      (result as RoomArModelIntegrityRejected).reason,
      contains('bounding box'),
    );
  });

  test(
    'unsafe metadata (URL as storage path) is rejected before any fetch',
    () async {
      final storage = FakeStorageSource(chairGlb);
      final meta = ProductArMetadata(
        storagePath: 'https://example.com/model.glb',
        modelVersion: '1',
        sha256: sha256.convert(chairGlb).toString(),
        widthM: 0.7,
        depthM: 0.72,
        heightM: 0.82,
      );
      final result = await serviceWith(
        storage,
      ).resolve(productId: 'luna-accent-chair', metadata: meta);
      expect(result, isA<RoomArModelIntegrityRejected>());
      expect(storage.downloadCount, 0);
    },
  );

  test('a new model version invalidates the old cached entry', () async {
    final storage = FakeStorageSource(chairGlb);
    await serviceWith(storage).resolve(
      productId: 'luna-accent-chair',
      metadata: metaFor(chairGlb, version: '1'),
    );
    expect(storage.downloadCount, 1);

    final v2Glb = buildGlb(
      boxGltf(x: 0.70, y: 0.82, z: 0.72),
      bin: Uint8List(64),
    );
    final storage2 = FakeStorageSource(v2Glb);
    final r = await serviceWith(storage2).resolve(
      productId: 'luna-accent-chair',
      metadata: metaFor(
        v2Glb,
        version: '2',
        path: 'products/luna-accent-chair/ar/model-v2.glb',
      ),
    );
    expect(storage2.downloadCount, 1); // did NOT serve the v1 entry
    expect((r as RoomArModelReady).source, RoomArModelSource.freshDownload);
  });

  test(
    'cachedOnly returns a verified entry without touching the network',
    () async {
      final storage = FakeStorageSource(chairGlb);
      final meta = metaFor(chairGlb);
      final service = serviceWith(storage);
      expect(
        await service.cachedOnly(
          productId: 'luna-accent-chair',
          metadata: meta,
        ),
        isNull,
      );
      await service.resolve(productId: 'luna-accent-chair', metadata: meta);
      final hit = await service.cachedOnly(
        productId: 'luna-accent-chair',
        metadata: meta,
      );
      expect(hit, isNotNull);
      expect(hit!.source, RoomArModelSource.verifiedCache);
    },
  );

  test('cachedOnly re-hashes the exact-cache entry and rejects same-size '
      'corruption (parity with resolve)', () async {
    final meta = metaFor(chairGlb);
    final service = serviceWith(FakeStorageSource(chairGlb));
    await service.resolve(productId: 'luna-accent-chair', metadata: meta);

    // corrupt the promoted cache file in place, keeping its exact length
    final modelFile = tempRoot
        .listSync(recursive: true)
        .whereType<File>()
        .firstWhere((f) => f.path.replaceAll('\\', '/').endsWith('/model.glb'));
    final bytes = Uint8List.fromList(await modelFile.readAsBytes());
    bytes[bytes.length - 3] ^= 0xFF;
    await modelFile.writeAsBytes(bytes, flush: true);

    final hit = await service.cachedOnly(
      productId: 'luna-accent-chair',
      metadata: meta,
    );
    // never the corrupted exact-cache file; the entry was evicted
    expect(await modelFile.exists(), isFalse);
    expect(hit?.source, anyOf(isNull, equals(RoomArModelSource.lastKnownGood)));

    // with the last-known-good also gone, cachedOnly returns null
    final lkg = File('${tempRoot.path}/lkg/luna-accent-chair.glb');
    if (await lkg.exists()) await lkg.delete();
    expect(
      await service.cachedOnly(productId: 'luna-accent-chair', metadata: meta),
      isNull,
    );
  });

  test('every terminal state carries a customer-safe message', () async {
    final storage = FakeStorageSource(chairGlb)
      ..failWith = const RoomArModelStorageException(
        RoomArModelStorageErrorKind.unknown,
        'boom-internal-detail',
      );
    final result = await serviceWith(
      storage,
    ).resolve(productId: 'luna-accent-chair', metadata: metaFor(chairGlb));
    expect(result, isA<RoomArModelFailed>());
    final msg = (result as RoomArModelFailed).message;
    expect(msg, isNot(contains('boom-internal-detail')));
    expect(msg.endsWith('.'), isTrue);
  });

  // ── R10 audit pass: evict + last-known-good read-time integrity ──────────

  File lkgFile() => File('${tempRoot.path}/lkg/luna-accent-chair.glb');
  File lkgSidecar() => File('${tempRoot.path}/lkg/luna-accent-chair.json');

  test(
    'evictCachedEntry forces a re-download and, offline, serves the same-version '
    'last-known-good (deterministic LKG path)',
    () async {
      final meta = metaFor(chairGlb, version: '1');
      final ok = FakeStorageSource(chairGlb);
      await serviceWith(
        ok,
      ).resolve(productId: 'luna-accent-chair', metadata: meta);
      expect(ok.downloadCount, 1);
      expect(await lkgFile().exists(), isTrue);

      // Evict ONLY the versioned cache entry — the LKG copy stays.
      await serviceWith(
        ok,
      ).evictCachedEntry(productId: 'luna-accent-chair', metadata: meta);
      expect(await lkgFile().exists(), isTrue);

      final offline = FakeStorageSource(chairGlb)
        ..failWith = const RoomArModelStorageException(
          RoomArModelStorageErrorKind.offline,
          'no network',
        );
      final result = await serviceWith(
        offline,
      ).resolve(productId: 'luna-accent-chair', metadata: meta);
      expect(offline.downloadCount, 1); // it DID try to download
      expect(result, isA<RoomArModelReady>());
      expect(
        (result as RoomArModelReady).source,
        RoomArModelSource.lastKnownGood,
      );
    },
  );

  test('a same-size but corrupted last-known-good is never rendered and is '
      'invalidated', () async {
    final meta = metaFor(chairGlb, version: '1');
    await serviceWith(
      FakeStorageSource(chairGlb),
    ).resolve(productId: 'luna-accent-chair', metadata: meta);
    await serviceWith(
      FakeStorageSource(chairGlb),
    ).evictCachedEntry(productId: 'luna-accent-chair', metadata: meta);

    // Corrupt the LKG bytes in place, keeping the exact length (so the
    // sidecar size check alone would pass).
    final corrupt = Uint8List.fromList(await lkgFile().readAsBytes());
    corrupt[corrupt.length - 5] ^= 0xFF;
    await lkgFile().writeAsBytes(corrupt, flush: true);

    final offline = FakeStorageSource(chairGlb)
      ..failWith = const RoomArModelStorageException(
        RoomArModelStorageErrorKind.offline,
        'no network',
      );
    final result = await serviceWith(
      offline,
    ).resolve(productId: 'luna-accent-chair', metadata: meta);

    expect(result, isA<RoomArModelOffline>());
    expect(await lkgFile().exists(), isFalse); // invalidated
    expect(await lkgSidecar().exists(), isFalse);
  });

  test('cachedOnly rejects a corrupted last-known-good', () async {
    final meta = metaFor(chairGlb, version: '1');
    final service = serviceWith(FakeStorageSource(chairGlb));
    await service.resolve(productId: 'luna-accent-chair', metadata: meta);
    await service.evictCachedEntry(
      productId: 'luna-accent-chair',
      metadata: meta,
    );

    final corrupt = Uint8List.fromList(await lkgFile().readAsBytes());
    corrupt[10] ^= 0xFF;
    await lkgFile().writeAsBytes(corrupt, flush: true);

    final hit = await service.cachedOnly(
      productId: 'luna-accent-chair',
      metadata: meta,
    );
    expect(hit, isNull);
    expect(await lkgFile().exists(), isFalse);
  });

  test(
    'a last-known-good whose sidecar was tampered to match corrupt bytes still '
    'fails the container check',
    () async {
      final meta = metaFor(chairGlb, version: '1');
      final service = serviceWith(FakeStorageSource(chairGlb));
      await service.resolve(productId: 'luna-accent-chair', metadata: meta);
      await service.evictCachedEntry(
        productId: 'luna-accent-chair',
        metadata: meta,
      );

      // Break the GLB magic bytes, then rewrite the sidecar's sha256 (and keep
      // size) so only the structural check can catch it.
      final broken = Uint8List.fromList(await lkgFile().readAsBytes());
      broken[0] = 0x00;
      await lkgFile().writeAsBytes(broken, flush: true);
      final sc =
          json.decode(await lkgSidecar().readAsString())
              as Map<String, dynamic>;
      sc['sha256'] = sha256.convert(broken).toString();
      await lkgSidecar().writeAsString(json.encode(sc), flush: true);

      final offline = FakeStorageSource(chairGlb)
        ..failWith = const RoomArModelStorageException(
          RoomArModelStorageErrorKind.offline,
          'no network',
        );
      final result = await serviceWith(
        offline,
      ).resolve(productId: 'luna-accent-chair', metadata: meta);
      expect(result, isA<RoomArModelOffline>());
      expect(await lkgFile().exists(), isFalse);
    },
  );
}
