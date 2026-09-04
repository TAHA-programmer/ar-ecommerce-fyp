import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../core/models/product/product_ar_metadata.dart';
import 'glb_inspector.dart';
import 'room_ar_model_cache.dart';
import 'room_ar_model_state.dart';
import 'room_ar_model_storage_source.dart';

/// Secure delivery of a product's Room-AR GLB from Firebase Storage to a
/// verified on-disk file the renderer can safely load (Phase 9.2 R10).
///
/// Contract (nothing here trusts a filename, a MIME type, or "the download
/// succeeded"):
///  * fetch strictly by the Firebase Storage **object path** in
///    [ProductArMetadata.storagePath] — never a download URL;
///  * download into a private staging file, enforce a hard maximum size;
///  * verify GLB magic bytes, declared length, chunk structure, the SHA-256
///    against [ProductArMetadata.sha256], and the bounding box against the
///    declared W/D/H within ±3 % — *before* the file is exposed;
///  * atomically promote only a fully verified file into a cache keyed by
///    path + version + SHA-256;
///  * deduplicate concurrent requests for the same model;
///  * re-serve an already verified cache entry with no network;
///  * on a failed refresh, fall back to the last verified copy of that product
///    ("last-known-good"), never to unverified bytes;
///  * emit only typed, customer-safe [RoomArModelState]s — never a raw
///    exception.
///
/// The bundled Android-asset GLBs remain the renderer's fallback until remote
/// delivery is physically approved; that decision belongs to the integration
/// layer, not this service — see [RoomArModelSource.bundledFallback].
abstract class RoomArModelService {
  /// Resolve a verified GLB for [productId]. [onState] receives every
  /// transition (checking cache → downloading → verifying → terminal); the
  /// returned future completes with the terminal state. Never throws.
  Future<RoomArModelState> resolve({
    required String productId,
    required ProductArMetadata metadata,
    void Function(RoomArModelState state)? onState,
  });

  /// A verified cached file (or a revalidated last-known-good) for [productId]
  /// with no network access at all, or null when nothing safe is on disk.
  Future<RoomArModelReady?> cachedOnly({
    required String productId,
    required ProductArMetadata metadata,
  });

  /// Delete **only** the exact versioned cache entry for this
  /// path+version+SHA-256, leaving the product's last-known-good copy intact.
  /// Used by the debug R10 verification surface to force the next [resolve]
  /// down the download / offline / last-known-good path. Not a customer path.
  Future<void> evictCachedEntry({
    required String productId,
    required ProductArMetadata metadata,
  });
}

class DefaultRoomArModelService implements RoomArModelService {
  DefaultRoomArModelService({
    required RoomArModelStorageSource storageSource,
    required RoomArModelCache modelCache,
    GlbInspector glbInspector = const GlbInspector(),
    int maxBytes = defaultMaxDownloadBytes,
    bool revalidateCache = true,
  }) : _storage = storageSource,
       _cache = modelCache,
       _inspector = glbInspector,
       _maxDownloadBytes = maxBytes,
       _revalidateCachedBytes = revalidateCache;

  /// 12 MiB — comfortably above the largest approved GLB (chair ≈ 1.6 MB) and
  /// the `SCALE_CONTRACT.md` 8 MB hard cap, below anything that would be a
  /// memory / egress problem on a mid-range phone. Also the ceiling enforced by
  /// `storage.rules` for the AR-model path.
  static const int defaultMaxDownloadBytes = 12 * 1024 * 1024;

  final RoomArModelStorageSource _storage;
  final RoomArModelCache _cache;
  final GlbInspector _inspector;
  final int _maxDownloadBytes;
  final bool _revalidateCachedBytes;

  /// Keyed by cache-key directory name: one in-flight resolution per exact
  /// model, so N concurrent callers trigger exactly one download.
  final Map<String, Future<RoomArModelState>> _inFlight = {};

  bool _sweptTemp = false;

  @override
  Future<RoomArModelState> resolve({
    required String productId,
    required ProductArMetadata metadata,
    void Function(RoomArModelState state)? onState,
  }) async {
    if (!metadata.isRenderable) {
      return _emit(
        onState,
        const RoomArModelIntegrityRejected(
          'the stored AR model details are incomplete or unsafe',
        ),
      );
    }

    final key = RoomArModelCacheKey(
      storagePath: metadata.storagePath,
      modelVersion: metadata.modelVersion,
      sha256: metadata.sha256,
    );

    if (!_sweptTemp) {
      _sweptTemp = true;
      unawaited(_cache.cleanupTemp());
    }

    final existing = _inFlight[key.directoryName];
    if (existing != null) {
      final terminal = await existing;
      onState?.call(terminal);
      return terminal;
    }

    final future = _resolve(productId, metadata, key, onState);
    _inFlight[key.directoryName] = future;
    try {
      return await future;
    } finally {
      _inFlight.remove(key.directoryName);
    }
  }

  @override
  Future<RoomArModelReady?> cachedOnly({
    required String productId,
    required ProductArMetadata metadata,
  }) async {
    if (!metadata.isRenderable) return null;
    final key = RoomArModelCacheKey(
      storagePath: metadata.storagePath,
      modelVersion: metadata.modelVersion,
      sha256: metadata.sha256,
    );
    final cached = await _cache.verifiedFile(key);
    if (cached != null) {
      // Re-hash the exact-cache bytes against current metadata — same guard as
      // resolve(). `verifiedFile` only checked the sidecar + on-disk size, so
      // same-size corruption would otherwise slip through here.
      if (!_revalidateCachedBytes ||
          await _sha256OfFile(cached) == metadata.sha256) {
        final meta = await _cache.metaFor(key);
        return RoomArModelReady(
          source: RoomArModelSource.verifiedCache,
          file: cached,
          measuredBox: _boxOf(meta),
        );
      }
      _log('cachedOnly: exact-cache SHA-256 mismatch — evicting the entry');
      await _cache.evictEntry(key);
    }
    // Last-known-good is fully revalidated (SHA-256 + container + dimensions
    // against its own sidecar) before it is ever returned.
    return _lkgReady(productId);
  }

  @override
  Future<void> evictCachedEntry({
    required String productId,
    required ProductArMetadata metadata,
  }) async {
    if (!metadata.isRenderable) return;
    await _cache.evictEntry(
      RoomArModelCacheKey(
        storagePath: metadata.storagePath,
        modelVersion: metadata.modelVersion,
        sha256: metadata.sha256,
      ),
    );
  }

  // ── core ────────────────────────────────────────────────────────────────

  Future<RoomArModelState> _resolve(
    String productId,
    ProductArMetadata metadata,
    RoomArModelCacheKey key,
    void Function(RoomArModelState)? onState,
  ) async {
    _emit(onState, const RoomArModelCheckingCache());

    // 1) Reuse an already-verified cache entry (no network).
    final cached = await _cache.verifiedFile(key);
    if (cached != null) {
      if (!_revalidateCachedBytes ||
          await _sha256OfFile(cached) == metadata.sha256) {
        final meta = await _cache.metaFor(key);
        // Refresh the last-known-good pointer opportunistically — but only from
        // a full sidecar (with dimensions), so a later LKG revalidation always
        // has something to check against.
        unawaited(_safeRecordLkg(productId, cached, meta));
        return _emit(
          onState,
          RoomArModelReady(
            source: RoomArModelSource.verifiedCache,
            file: cached,
            measuredBox: _boxOf(meta),
          ),
        );
      }
      // On-disk corruption — drop it and re-download.
      try {
        await cached.delete();
      } catch (_) {}
    }

    // 2) Download into a private staging file.
    _emit(onState, const RoomArModelDownloading());
    final tmp = await _cache.newTempFile(key);
    try {
      await _storage.downloadTo(
        metadata.storagePath,
        tmp,
        maxBytes: _maxDownloadBytes,
        onProgress: (received, total) {
          _emit(
            onState,
            RoomArModelDownloading(
              progress: (total != null && total > 0)
                  ? (received / total).clamp(0.0, 1.0)
                  : null,
            ),
          );
        },
      );
    } on RoomArModelStorageException catch (e) {
      await _discard(tmp);
      return _emit(onState, await _afterFailedRefresh(productId, e));
    } catch (e) {
      await _discard(tmp);
      _log('unexpected download error: $e');
      return _emit(
        onState,
        await _afterFailedRefresh(
          productId,
          const RoomArModelStorageException(
            RoomArModelStorageErrorKind.unknown,
            'unexpected download error',
          ),
        ),
      );
    }

    // 3) Verify before anything is exposed.
    _emit(onState, const RoomArModelVerifying());
    final Uint8List bytes;
    try {
      bytes = await tmp.readAsBytes();
    } catch (e) {
      await _discard(tmp);
      _log('could not read staged file: $e');
      return _emit(
        onState,
        await _afterFailedRefresh(
          productId,
          const RoomArModelStorageException(
            RoomArModelStorageErrorKind.unknown,
            'staged file unreadable',
          ),
        ),
      );
    }

    if (bytes.length > _maxDownloadBytes) {
      await _discard(tmp);
      return _emit(
        onState,
        await _rejectOrLkgAsync(
          productId,
          'the AR model file is larger than allowed',
        ),
      );
    }

    final structure = _inspector.inspect(
      bytes,
      expected: GlbExpectedBox(
        widthM: metadata.widthM,
        depthM: metadata.depthM,
        heightM: metadata.heightM,
      ),
      maxBytes: _maxDownloadBytes,
    );
    if (!structure.ok) {
      await _discard(tmp);
      _log(
        'glb structural/bbox rejection: ${structure.rejectionReason} '
        '(measured ${structure.width}x${structure.depth}x${structure.height} m)',
      );
      return _emit(
        onState,
        await _rejectOrLkgAsync(
          productId,
          structure.rejectionReason ?? 'the AR model failed validation',
        ),
      );
    }

    final actualSha = sha256.convert(bytes).toString();
    if (actualSha != metadata.sha256) {
      await _discard(tmp);
      _log('sha-256 mismatch: expected ${metadata.sha256}, got $actualSha');
      return _emit(
        onState,
        await _rejectOrLkgAsync(
          productId,
          'the downloaded AR model did not match its expected checksum',
        ),
      );
    }

    // 4) Promote atomically + record last-known-good.
    final meta = RoomArModelCacheMeta(
      storagePath: metadata.storagePath,
      modelVersion: metadata.modelVersion,
      sha256: metadata.sha256,
      sizeBytes: bytes.length,
      verifiedAtIso: DateTime.now().toUtc().toIso8601String(),
      widthM: structure.width,
      depthM: structure.depth,
      heightM: structure.height,
    );
    File promoted;
    try {
      promoted = await _cache.promote(tmp, key, meta);
      await _cache.recordLastKnownGood(productId, promoted, meta);
    } catch (e) {
      await _discard(tmp);
      _log('promotion failed: $e');
      return _emit(
        onState,
        const RoomArModelFailed('Could not save the AR model. Please retry.'),
      );
    }

    return _emit(
      onState,
      RoomArModelReady(
        source: RoomArModelSource.freshDownload,
        file: promoted,
        measuredBox: (
          width: structure.width,
          depth: structure.depth,
          height: structure.height,
        ),
      ),
    );
  }

  // ── failure handling ────────────────────────────────────────────────────

  /// A download failed. Prefer a previously verified copy of this product;
  /// otherwise map to the most honest terminal state.
  Future<RoomArModelState> _afterFailedRefresh(
    String productId,
    RoomArModelStorageException e,
  ) async {
    final lkg = await _lkgReady(productId);
    if (lkg != null) return lkg;
    switch (e.kind) {
      case RoomArModelStorageErrorKind.offline:
        return const RoomArModelOffline();
      case RoomArModelStorageErrorKind.notFound:
        return const RoomArModelFailed(
          'This product\'s AR model is not available yet.',
        );
      case RoomArModelStorageErrorKind.permissionDenied:
        return const RoomArModelFailed(
          'You do not have access to this AR model.',
        );
      case RoomArModelStorageErrorKind.tooLarge:
        return const RoomArModelFailed(
          'The AR model file is too large to download safely.',
        );
      case RoomArModelStorageErrorKind.unknown:
        return const RoomArModelFailed(
          'Could not download the AR model. Please try again.',
        );
    }
  }

  /// A downloaded file was rejected. Surface the rejection, but if a
  /// previously verified copy exists, decide it as the usable terminal (the
  /// caller's [onState] history still shows the rejection).
  Future<RoomArModelState> _rejectOrLkgAsync(
    String productId,
    String reason,
  ) async {
    final lkg = await _lkgReady(productId);
    return lkg ?? RoomArModelIntegrityRejected(reason);
  }

  /// Return a [RoomArModelReady] for the product's last-known-good copy **only
  /// after** revalidating it end to end — a corrupted or drifted LKG is never
  /// handed to Filament. The LKG is checked against **its own sidecar** (which
  /// records the LKG's real hash + dimensions), never against a newer
  /// requested model's hash/version.
  Future<RoomArModelReady?> _lkgReady(String productId) async {
    final lkg = await _cache.lastKnownGood(productId);
    if (lkg == null) return null;
    final meta = await _cache.lastKnownGoodMeta(productId);
    if (!await _revalidateLkg(productId, lkg, meta)) return null;
    return RoomArModelReady(
      source: RoomArModelSource.lastKnownGood,
      file: lkg,
      measuredBox: _boxOf(meta),
    );
  }

  static final _shaRe = RegExp(r'^[0-9a-f]{64}$');

  Future<bool> _revalidateLkg(
    String productId,
    File lkg,
    RoomArModelCacheMeta? meta,
  ) async {
    Future<void> drop(String why) async {
      _log('LKG revalidation failed for $productId ($why) — invalidating');
      await _cache.invalidateLastKnownGood(productId);
    }

    if (meta == null ||
        !_shaRe.hasMatch(meta.sha256) ||
        meta.sizeBytes <= 0 ||
        meta.widthM == null ||
        meta.depthM == null ||
        meta.heightM == null) {
      await drop('incomplete sidecar');
      return false;
    }

    final Uint8List bytes;
    try {
      bytes = await lkg.readAsBytes();
    } catch (e) {
      await drop('unreadable: $e');
      return false;
    }
    if (bytes.length != meta.sizeBytes) {
      await drop('size drift');
      return false;
    }
    if (sha256.convert(bytes).toString() != meta.sha256) {
      await drop('sha-256 mismatch');
      return false;
    }
    final structure = _inspector.inspect(
      bytes,
      expected: GlbExpectedBox(
        widthM: meta.widthM!,
        depthM: meta.depthM!,
        heightM: meta.heightM!,
      ),
      maxBytes: _maxDownloadBytes,
    );
    if (!structure.ok) {
      await drop('container/bbox: ${structure.rejectionReason}');
      return false;
    }
    return true;
  }

  // ── helpers ─────────────────────────────────────────────────────────────

  Future<void> _safeRecordLkg(
    String productId,
    File cached,
    RoomArModelCacheMeta? meta,
  ) async {
    if (meta == null ||
        meta.widthM == null ||
        meta.depthM == null ||
        meta.heightM == null) {
      return; // never record a dimensionless LKG
    }
    try {
      await _cache.recordLastKnownGood(productId, cached, meta);
    } catch (_) {
      // Best-effort — a stale LKG pointer is never worse than none.
    }
  }

  Future<void> _discard(File tmp) async {
    try {
      if (await tmp.exists()) await tmp.delete();
    } catch (_) {}
  }

  Future<String> _sha256OfFile(File f) async =>
      sha256.convert(await f.readAsBytes()).toString();

  ({double width, double depth, double height})? _boxOf(
    RoomArModelCacheMeta? meta,
  ) {
    if (meta?.widthM == null || meta?.depthM == null || meta?.heightM == null) {
      return null;
    }
    return (width: meta!.widthM!, depth: meta.depthM!, height: meta.heightM!);
  }

  RoomArModelState _emit(
    void Function(RoomArModelState)? onState,
    RoomArModelState state,
  ) {
    onState?.call(state);
    return state;
  }

  void _log(String message) {
    if (kDebugMode) debugPrint('[RoomArModelService] $message');
  }
}
