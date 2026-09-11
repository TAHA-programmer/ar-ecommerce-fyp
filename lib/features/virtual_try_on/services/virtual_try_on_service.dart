import 'dart:typed_data';

/// The successful outcome of [VirtualTryOnService.generate] — mirrors
/// `generateTryOn`'s `GenerateTryOnResult` (`functions/src/generateTryOn.ts`).
class VirtualTryOnGenerateResult {
  final String sessionId;
  final String resultPath;

  /// Real, server-stated expiry (never estimated client-side) — the D4 24h
  /// TTL, or the true remaining lifetime of a cached-success replay.
  final DateTime expiresAt;
  final String provider;
  final String providerModel;

  const VirtualTryOnGenerateResult({
    required this.sessionId,
    required this.resultPath,
    required this.expiresAt,
    required this.provider,
    required this.providerModel,
  });
}

/// Outcome of [VirtualTryOnService.deleteAllTryOnData] — lets the caller show
/// truthful feedback (success / partial-failure / failure) instead of always
/// claiming success regardless of what actually happened.
enum VirtualTryOnDataDeletionOutcome {
  /// The customer's `tryOnSessions` could be queried, and every Storage
  /// object any of them reference was deleted (or was already absent).
  success,

  /// The query succeeded, but at least one referenced Storage object could
  /// not be deleted for a reason other than "already gone" (e.g. a
  /// permission or network failure on that specific object).
  partial,

  /// The `tryOnSessions` query itself could not be completed (offline,
  /// permission, or any other failure) — nothing could be confirmed deleted.
  failed,
}

/// Result of [VirtualTryOnService.deleteAllTryOnData].
class VirtualTryOnDataDeletionResult {
  final VirtualTryOnDataDeletionOutcome outcome;

  /// Number of `tryOnSessions` documents found for this customer — `0` on
  /// [VirtualTryOnDataDeletionOutcome.failed] (the query never completed).
  final int sessionsFound;

  const VirtualTryOnDataDeletionResult({
    required this.outcome,
    required this.sessionsFound,
  });
}

/// Client seam for the Phase 9.3 Stage 4 `generateTryOn` backend — mirrors
/// [CheckoutPaymentService]'s role for `createPaymentIntent`. Every method
/// takes the caller's own [uid] explicitly (never reads `FirebaseAuth`
/// itself) so it stays a pure, fully-mockable seam; the ViewModel is
/// responsible for confirming the customer is signed in before calling any
/// of these.
///
/// [uploadPersonPhoto] and [generate] are deliberately separate calls (rather
/// than one combined method) so the ViewModel can show distinct "uploading"
/// vs "generating" progress states — both steps target the SAME
/// `(uid, idempotencyKey)` attempt, so [generate] must be called with the
/// exact same [idempotencyKey] just passed to [uploadPersonPhoto].
///
/// Implementations must never send anything beyond the callable's exact
/// allow-listed request shape (`productId`, `colorKey`, `size`,
/// `idempotencyKey`, `consent`) and must never surface a provider name,
/// credential, or raw backend error text to the caller — only a mapped
/// [VirtualTryOnException].
abstract class VirtualTryOnService {
  /// Deterministic session id for `(uid, idempotencyKey)` — MUST use the
  /// exact same algorithm as `tryOnSessionIdFor`
  /// (`functions/src/lib/tryOn/session.ts`): `sha256("$uid $idempotencyKey")`
  /// as lowercase hex. The client needs this to know its upload path before
  /// ever calling [generate].
  String deriveSessionId({required String uid, required String idempotencyKey});

  /// Uploads [personPhotoJpegBytes] (already validated + re-encoded to JPEG
  /// by `PersonPhotoProcessor`) to this attempt's exact Storage upload path.
  /// Throws [VirtualTryOnException] on failure — never a raw platform
  /// exception.
  Future<void> uploadPersonPhoto({
    required String uid,
    required String idempotencyKey,
    required Uint8List personPhotoJpegBytes,
  });

  /// Calls the `generateTryOn` callable with the exact allow-listed body.
  /// Assumes [uploadPersonPhoto] already succeeded for the SAME
  /// `(uid, idempotencyKey)`.
  ///
  /// On failure, best-effort deletes the uploaded photo before rethrowing —
  /// the server's own `finally` already deletes it for every call that
  /// reaches the function; this only covers the narrow case where the
  /// callable itself was never reached (a pure network failure).
  Future<VirtualTryOnGenerateResult> generate({
    required String uid,
    required String productId,
    required String colorKey,
    required String? size,
    required String idempotencyKey,
    required bool consent,
  });

  /// Authenticated download of a generated result's bytes
  /// (`ref.getData()` — never a signed URL).
  Future<Uint8List> downloadResult(String resultPath, {int maxSize});

  /// Best-effort delete of the person-photo upload for this
  /// `(uid, idempotencyKey)` attempt. Used when the customer cancels before
  /// [generate] is called, or after a failed/aborted [generate] — swallows
  /// "not found" and any other failure (never fatal to the caller).
  Future<void> deleteUploadBestEffort({
    required String uid,
    required String idempotencyKey,
  });

  /// Best-effort delete of a generated result — "Delete this preview" / D4's
  /// "leaves the completed result flow" primary deletion path. Swallows
  /// every failure (never fatal to the caller).
  Future<void> deleteResultBestEffort(String resultPath);

  /// Profile "Delete my try-on data" (tracker §5.2 step 10): removes every
  /// Storage object (uploads + results) this customer's own
  /// `tryOnSessions` docs reference. `tryOnSessions` documents themselves are
  /// never client-writable (`firestore.rules`) and are left in place as an
  /// activity record with no image data — only the media is deleted here.
  ///
  /// Never throws — returns a [VirtualTryOnDataDeletionResult] the caller
  /// can show truthfully instead of assuming success. An individual object
  /// that was already absent is not a failure (a session's photo/result may
  /// already be gone via the normal D4 paths or the TTL sweep); a genuine
  /// per-object failure (permission/network) is reflected in the outcome.
  Future<VirtualTryOnDataDeletionResult> deleteAllTryOnData({
    required String uid,
  });
}
