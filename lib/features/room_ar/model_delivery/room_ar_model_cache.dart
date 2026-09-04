import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:path_provider/path_provider.dart';

/// Identifies one exact verified GLB in the on-disk cache. The key deliberately
/// folds in the **Storage object path + model version + expected SHA-256**
/// (tracker §12 / R10) so that:
///  * a new model version, or the same path re-uploaded with different bytes,
///    is a *different* cache entry — the old one is never silently served;
///  * an entry can only ever hold bytes whose hash equals the one in its own
///    key, so "cache hit" and "integrity verified" are the same fact.
class RoomArModelCacheKey {
  RoomArModelCacheKey({
    required this.storagePath,
    required this.modelVersion,
    required this.sha256,
  });

  final String storagePath;
  final String modelVersion;
  final String sha256;

  static final _unsafe = RegExp(r'[^A-Za-z0-9._-]');

  /// Directory name under the cache root — filesystem-safe, collision-resistant,
  /// still legible for debugging.
  String get directoryName {
    final safePath = storagePath.replaceAll(_unsafe, '_');
    final safeVersion = modelVersion.replaceAll(_unsafe, '_');
    final shaPrefix = sha256.length >= 16 ? sha256.substring(0, 16) : sha256;
    return '${safePath}__v${safeVersion}__$shaPrefix';
  }
}

/// Sidecar metadata written next to every promoted cache file. Lets a later run
/// re-check "is this still the file the key promises" without re-hashing on the
/// hot path, and gives the debug surface something to show.
class RoomArModelCacheMeta {
  const RoomArModelCacheMeta({
    required this.storagePath,
    required this.modelVersion,
    required this.sha256,
    required this.sizeBytes,
    required this.verifiedAtIso,
    this.widthM,
    this.depthM,
    this.heightM,
  });

  final String storagePath;
  final String modelVersion;
  final String sha256;
  final int sizeBytes;
  final String verifiedAtIso;
  final double? widthM;
  final double? depthM;
  final double? heightM;

  Map<String, dynamic> toJson() => {
    'storagePath': storagePath,
    'modelVersion': modelVersion,
    'sha256': sha256,
    'sizeBytes': sizeBytes,
    'verifiedAt': verifiedAtIso,
    if (widthM != null) 'widthM': widthM,
    if (depthM != null) 'depthM': depthM,
    if (heightM != null) 'heightM': heightM,
  };

  static RoomArModelCacheMeta? tryParse(String raw) {
    try {
      final m = json.decode(raw) as Map<String, dynamic>;
      return RoomArModelCacheMeta(
        storagePath: m['storagePath'] as String,
        modelVersion: m['modelVersion'].toString(),
        sha256: m['sha256'] as String,
        sizeBytes: (m['sizeBytes'] as num).toInt(),
        verifiedAtIso: m['verifiedAt'] as String,
        widthM: (m['widthM'] as num?)?.toDouble(),
        depthM: (m['depthM'] as num?)?.toDouble(),
        heightM: (m['heightM'] as num?)?.toDouble(),
      );
    } catch (_) {
      return null;
    }
  }
}

/// On-disk cache for verified Room-AR GLBs. Everything the renderer is ever
/// handed comes from here, and only after atomic promotion — a partially
/// written or unverified file is never reachable through any public method.
class RoomArModelCache {
  RoomArModelCache(this._root);

  /// Resolves the real per-app cache directory (`getApplicationCacheDirectory`,
  /// which the OS may evict under storage pressure — appropriate for
  /// re-downloadable assets). Tests construct [RoomArModelCache] directly with a
  /// temp dir instead.
  static Future<RoomArModelCache> open() async {
    final base = await getApplicationCacheDirectory();
    final root = Directory('${base.path}/room_ar_models');
    await root.create(recursive: true);
    return RoomArModelCache(root);
  }

  final Directory _root;
  final _rand = Random();

  Directory get _tmpDir => Directory('${_root.path}/.tmp');
  Directory get _lkgDir => Directory('${_root.path}/lkg');

  static final _unsafe = RegExp(r'[^A-Za-z0-9._-]');

  // ── verified cache entries ───────────────────────────────────────────────

  File _modelFileFor(RoomArModelCacheKey key) =>
      File('${_root.path}/${key.directoryName}/model.glb');
  File _metaFileFor(RoomArModelCacheKey key) =>
      File('${_root.path}/${key.directoryName}/meta.json');

  /// The promoted, verified file for [key] if one exists and its sidecar still
  /// agrees with the key (path/version/sha) and the on-disk size. Returns null
  /// otherwise — the caller then (re)downloads. Never returns a `.tmp` path.
  Future<File?> verifiedFile(RoomArModelCacheKey key) async {
    final file = _modelFileFor(key);
    if (!await file.exists()) return null;
    final metaFile = _metaFileFor(key);
    if (!await metaFile.exists()) return null;
    final meta = RoomArModelCacheMeta.tryParse(await metaFile.readAsString());
    if (meta == null) return null;
    if (meta.sha256 != key.sha256 ||
        meta.modelVersion != key.modelVersion ||
        meta.storagePath != key.storagePath) {
      return null;
    }
    if (await file.length() != meta.sizeBytes) return null;
    return file;
  }

  Future<RoomArModelCacheMeta?> metaFor(RoomArModelCacheKey key) async {
    final metaFile = _metaFileFor(key);
    if (!await metaFile.exists()) return null;
    return RoomArModelCacheMeta.tryParse(await metaFile.readAsString());
  }

  /// Delete **only** the exact versioned cache entry for [key] (its
  /// `model.glb` + `meta.json` + the entry directory). The per-product
  /// last-known-good copy under `lkg/` is deliberately left intact — evicting
  /// the entry is exactly how the R10 debug surface forces the next `resolve`
  /// down the download / offline / last-known-good path. Best-effort.
  Future<void> evictEntry(RoomArModelCacheKey key) async {
    final dir = Directory('${_root.path}/${key.directoryName}');
    try {
      if (await dir.exists()) await dir.delete(recursive: true);
    } catch (_) {}
  }

  /// A fresh, unique staging path under `.tmp/`. The caller downloads into it,
  /// verifies it, then calls [promote]. Files here are never returned to the
  /// renderer and are swept by [cleanupTemp].
  Future<File> newTempFile(RoomArModelCacheKey key) async {
    await _tmpDir.create(recursive: true);
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final salt = _rand.nextInt(1 << 32).toRadixString(16);
    return File('${_tmpDir.path}/${key.directoryName}-$stamp-$salt.glb');
  }

  /// Atomically move an already-verified [tempFile] into the cache entry for
  /// [key] and write its sidecar. Returns the promoted file. After this
  /// returns, [verifiedFile] for the same key yields the same path.
  Future<File> promote(
    File tempFile,
    RoomArModelCacheKey key,
    RoomArModelCacheMeta meta,
  ) async {
    final target = _modelFileFor(key);
    await target.parent.create(recursive: true);
    // A rename over an existing file is not portable (Windows); clear first.
    if (await target.exists()) {
      await target.delete();
    }
    File promoted;
    try {
      promoted = await tempFile.rename(target.path);
    } on FileSystemException {
      // Cross-device or locked target: fall back to copy + delete, still not
      // exposing the temp path as the returned handle.
      promoted = await tempFile.copy(target.path);
      try {
        await tempFile.delete();
      } catch (_) {}
    }
    await _writeAtomic(_metaFileFor(key), json.encode(meta.toJson()));
    return promoted;
  }

  // ── last-known-good (per product) ────────────────────────────────────────

  String _safeProductId(String productId) => productId.replaceAll(_unsafe, '_');

  File _lkgModelFile(String productId) =>
      File('${_lkgDir.path}/${_safeProductId(productId)}.glb');
  File _lkgMetaFile(String productId) =>
      File('${_lkgDir.path}/${_safeProductId(productId)}.json');

  /// Record [promoted] as the last-known-good model for [productId], replacing
  /// any previous one. Called after every successful verify+promote so a future
  /// failed refresh has something safe to fall back to.
  Future<void> recordLastKnownGood(
    String productId,
    File promoted,
    RoomArModelCacheMeta meta,
  ) async {
    await _lkgDir.create(recursive: true);
    final tmp = File(
      '${_lkgDir.path}/${_safeProductId(productId)}.glb.'
      '${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await promoted.copy(tmp.path);
    final target = _lkgModelFile(productId);
    if (await target.exists()) await target.delete();
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      await tmp.copy(target.path);
      try {
        await tmp.delete();
      } catch (_) {}
    }
    await _writeAtomic(_lkgMetaFile(productId), json.encode(meta.toJson()));
  }

  /// The last-known-good file for [productId], if one was ever recorded and it
  /// still matches its sidecar size. May be an older model version than the
  /// one currently requested — that is the point.
  Future<File?> lastKnownGood(String productId) async {
    final file = _lkgModelFile(productId);
    if (!await file.exists()) return null;
    final metaFile = _lkgMetaFile(productId);
    if (!await metaFile.exists()) return null;
    final meta = RoomArModelCacheMeta.tryParse(await metaFile.readAsString());
    if (meta == null) return null;
    if (await file.length() != meta.sizeBytes) return null;
    return file;
  }

  Future<RoomArModelCacheMeta?> lastKnownGoodMeta(String productId) async {
    final metaFile = _lkgMetaFile(productId);
    if (!await metaFile.exists()) return null;
    return RoomArModelCacheMeta.tryParse(await metaFile.readAsString());
  }

  /// Remove a last-known-good copy that failed read-time revalidation (bad
  /// SHA-256, broken container, dimensions outside tolerance). After this the
  /// product simply has no LKG until the next successful verify+promote.
  /// Best-effort.
  Future<void> invalidateLastKnownGood(String productId) async {
    for (final f in [_lkgModelFile(productId), _lkgMetaFile(productId)]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  // ── housekeeping ─────────────────────────────────────────────────────────

  /// Delete stray staging files (a crash mid-download, a rejected file). Safe
  /// to call on every service start.
  Future<void> cleanupTemp() async {
    if (!await _tmpDir.exists()) return;
    await for (final entity in _tmpDir.list()) {
      if (entity is File) {
        try {
          await entity.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _writeAtomic(File target, String contents) async {
    final tmp = File(
      '${target.path}.${DateTime.now().microsecondsSinceEpoch}.tmp',
    );
    await tmp.writeAsString(contents, flush: true);
    if (await target.exists()) await target.delete();
    try {
      await tmp.rename(target.path);
    } on FileSystemException {
      await tmp.copy(target.path);
      try {
        await tmp.delete();
      } catch (_) {}
    }
  }
}
