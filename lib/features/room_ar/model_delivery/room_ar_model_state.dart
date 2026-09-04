import 'dart:io';

/// Where a resolved Room-AR GLB physically came from. Surfaced in the debug
/// verification surface (R10) and used by the renderer-handoff layer to decide
/// whether it is loading an external verified file or falling back to the
/// bundled Android asset.
enum RoomArModelSource {
  /// A freshly downloaded, freshly verified file that was just promoted into
  /// the cache.
  freshDownload,

  /// An already-verified file re-served from the on-disk cache (no network).
  verifiedCache,

  /// A previously verified file for this product, re-served because a later
  /// refresh failed (bad network / rejected new bytes). May be an older
  /// model version.
  lastKnownGood,

  /// No verified external file is available; the caller must use the GLB
  /// bundled in the app (temporary R10 fallback until remote delivery is
  /// physically approved).
  bundledFallback,
}

/// Immutable, customer-safe state of a Room-AR model resolution
/// ([RoomArModelService.resolve]). Deliberately a small sealed hierarchy so a
/// UI can `switch` over it with no raw exception ever reaching the surface.
sealed class RoomArModelState {
  const RoomArModelState();
}

/// Nothing requested yet.
class RoomArModelIdle extends RoomArModelState {
  const RoomArModelIdle();
}

/// Looking for an already-verified cached copy (fast, no network).
class RoomArModelCheckingCache extends RoomArModelState {
  const RoomArModelCheckingCache();
}

/// Downloading from Firebase Storage. [progress] is `0.0..1.0` when the total
/// size is known, otherwise null (indeterminate).
class RoomArModelDownloading extends RoomArModelState {
  const RoomArModelDownloading({this.progress});
  final double? progress;
}

/// Bytes are on disk; running magic-byte / length / structure / SHA-256 /
/// bounding-box checks before anything reaches the renderer.
class RoomArModelVerifying extends RoomArModelState {
  const RoomArModelVerifying();
}

/// A verified file is ready. [file] is always a promoted cache path (never a
/// `.tmp` / partial file) for every [source] except [RoomArModelSource
/// .bundledFallback], where it is null and the caller uses the bundled asset.
class RoomArModelReady extends RoomArModelState {
  const RoomArModelReady({required this.source, this.file, this.measuredBox});

  final RoomArModelSource source;
  final File? file;

  /// Measured world-space `(width X, depth Z, height Y)` metres, when a
  /// bounding-box check ran. Null for a bundled fallback.
  final ({double width, double depth, double height})? measuredBox;

  bool get isBundledFallback => source == RoomArModelSource.bundledFallback;
}

/// Offline and no usable cached copy — a distinct, honest state (not a generic
/// error) so the surface can say "connect and retry" rather than "something
/// went wrong".
class RoomArModelOffline extends RoomArModelState {
  const RoomArModelOffline();
}

/// The bytes downloaded but failed a safety check (bad magic, truncated, SHA-256
/// mismatch, bounding box outside ±3 %, …). [reason] is a short customer-neutral
/// phrase; the full detail is logged, not shown. A rejected file is never
/// promoted and never reaches the renderer.
class RoomArModelIntegrityRejected extends RoomArModelState {
  const RoomArModelIntegrityRejected(this.reason);
  final String reason;
}

/// Any other terminal failure, already mapped to a single customer-safe
/// sentence.
class RoomArModelFailed extends RoomArModelState {
  const RoomArModelFailed(this.message);
  final String message;
}

extension RoomArModelStateX on RoomArModelState {
  bool get isTerminal =>
      this is RoomArModelReady ||
      this is RoomArModelOffline ||
      this is RoomArModelIntegrityRejected ||
      this is RoomArModelFailed;

  /// One short line for the debug verification surface.
  String get debugLabel => switch (this) {
    RoomArModelIdle() => 'idle',
    RoomArModelCheckingCache() => 'checking cache…',
    RoomArModelDownloading(:final progress) =>
      progress == null
          ? 'downloading…'
          : 'downloading ${(progress * 100).round()}%',
    RoomArModelVerifying() => 'verifying…',
    RoomArModelReady(:final source) => switch (source) {
      RoomArModelSource.freshDownload => 'verified (fresh download)',
      RoomArModelSource.verifiedCache => 'verified (cache)',
      RoomArModelSource.lastKnownGood => 'last-known-good cache',
      RoomArModelSource.bundledFallback => 'bundled fallback',
    },
    RoomArModelOffline() => 'offline — no cached copy',
    RoomArModelIntegrityRejected(:final reason) => 'rejected: $reason',
    RoomArModelFailed(:final message) => 'failed: $message',
  };
}
