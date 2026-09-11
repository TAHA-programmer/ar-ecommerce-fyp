import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:crypto/crypto.dart';
import 'package:firebase_storage/firebase_storage.dart';

import 'virtual_try_on_exception.dart';
import 'virtual_try_on_service.dart';

/// Real [VirtualTryOnService]: the `generateTryOn` callable (Cloud Functions,
/// `us-central1`) + direct `firebase_storage` reads/writes on the exact
/// Stage-4 paths — mirrors [StripeCheckoutPaymentService]'s role and shape.
///
/// Never writes any Firestore document itself (`tryOnSessions`/`tryOnQuota`
/// are function-owned, client `write: false` in `firestore.rules`) and never
/// sends anything beyond the callable's allow-listed request body.
class FirebaseVirtualTryOnService implements VirtualTryOnService {
  static const String _functionsRegion = 'us-central1';

  final FirebaseFunctions? _injectedFunctions;
  final FirebaseStorage? _injectedStorage;
  final FirebaseFirestore? _injectedFirestore;

  FirebaseVirtualTryOnService({
    FirebaseFunctions? functions,
    FirebaseStorage? storage,
    FirebaseFirestore? firestore,
  }) : _injectedFunctions = functions,
       _injectedStorage = storage,
       _injectedFirestore = firestore;

  FirebaseFunctions get _functions =>
      _injectedFunctions ??
      FirebaseFunctions.instanceFor(region: _functionsRegion);

  FirebaseStorage get _storage => _injectedStorage ?? FirebaseStorage.instance;

  FirebaseFirestore get _firestore =>
      _injectedFirestore ?? FirebaseFirestore.instance;

  @override
  String deriveSessionId({
    required String uid,
    required String idempotencyKey,
  }) {
    return sha256.convert(utf8.encode('$uid $idempotencyKey')).toString();
  }

  String _uploadPath(String uid, String sessionId) =>
      'users/$uid/tryOnUploads/$sessionId.jpg';

  @override
  Future<void> uploadPersonPhoto({
    required String uid,
    required String idempotencyKey,
    required Uint8List personPhotoJpegBytes,
  }) async {
    final sessionId = deriveSessionId(uid: uid, idempotencyKey: idempotencyKey);
    try {
      await _storage
          .ref(_uploadPath(uid, sessionId))
          .putData(
            personPhotoJpegBytes,
            SettableMetadata(contentType: 'image/jpeg'),
          );
    } catch (_) {
      throw const VirtualTryOnException.network();
    }
  }

  @override
  Future<VirtualTryOnGenerateResult> generate({
    required String uid,
    required String productId,
    required String colorKey,
    required String? size,
    required String idempotencyKey,
    required bool consent,
  }) async {
    final sessionId = deriveSessionId(uid: uid, idempotencyKey: idempotencyKey);
    final uploadPath = _uploadPath(uid, sessionId);

    try {
      final callable = _functions.httpsCallable(
        'generateTryOn',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 130)),
      );
      final result = await callable.call(<String, dynamic>{
        'productId': productId,
        'colorKey': colorKey,
        'size': size,
        'idempotencyKey': idempotencyKey,
        'consent': consent,
      });

      final data = _asStringMap(result.data);
      final resultPath = (data?['resultPath'] as String?) ?? '';
      final expiresAtMs = (data?['expiresAt'] as num?)?.toInt();
      if (resultPath.isEmpty || expiresAtMs == null) {
        throw const VirtualTryOnException(
          VirtualTryOnErrorKind.unknown,
          'Something went wrong generating your preview. Please try again.',
        );
      }
      return VirtualTryOnGenerateResult(
        sessionId: (data?['sessionId'] as String?) ?? sessionId,
        resultPath: resultPath,
        expiresAt: DateTime.fromMillisecondsSinceEpoch(expiresAtMs),
        provider: (data?['provider'] as String?) ?? '',
        providerModel: (data?['providerModel'] as String?) ?? '',
      );
    } on FirebaseFunctionsException catch (e) {
      await _deleteUploadIgnoringErrors(uploadPath);
      throw _mapFunctionsException(e);
    } on VirtualTryOnException {
      await _deleteUploadIgnoringErrors(uploadPath);
      rethrow;
    } catch (_) {
      await _deleteUploadIgnoringErrors(uploadPath);
      throw const VirtualTryOnException.network();
    }
  }

  @override
  Future<Uint8List> downloadResult(
    String resultPath, {
    int maxSize = 15 * 1024 * 1024,
  }) async {
    try {
      final bytes = await _storage.ref(resultPath).getData(maxSize);
      if (bytes == null) {
        throw const VirtualTryOnException(
          VirtualTryOnErrorKind.unknown,
          "We couldn't load your preview. Please try again.",
        );
      }
      return bytes;
    } on VirtualTryOnException {
      rethrow;
    } catch (_) {
      throw const VirtualTryOnException.network();
    }
  }

  @override
  Future<void> deleteUploadBestEffort({
    required String uid,
    required String idempotencyKey,
  }) async {
    final sessionId = deriveSessionId(uid: uid, idempotencyKey: idempotencyKey);
    await _deleteUploadIgnoringErrors(_uploadPath(uid, sessionId));
  }

  @override
  Future<void> deleteResultBestEffort(String resultPath) async {
    try {
      await _storage.ref(resultPath).delete();
    } catch (_) {
      // Best-effort: already gone, or a transient failure. The TTL sweep
      // (`cleanupExpiredTryOnMedia`) is the safety net for anything left
      // behind.
    }
  }

  @override
  Future<VirtualTryOnDataDeletionResult> deleteAllTryOnData({
    required String uid,
  }) async {
    QuerySnapshot<Map<String, dynamic>> snapshot;
    try {
      snapshot = await _firestore
          .collection('tryOnSessions')
          .where('userId', isEqualTo: uid)
          .get();
    } catch (_) {
      // The query itself never completed - nothing can be confirmed
      // deleted. Never claim success here.
      return const VirtualTryOnDataDeletionResult(
        outcome: VirtualTryOnDataDeletionOutcome.failed,
        sessionsFound: 0,
      );
    }

    var anyObjectFailed = false;
    for (final doc in snapshot.docs) {
      final sessionId = doc.id;
      final uploadOk = await _deleteObjectTrackingFailure(
        _uploadPath(uid, sessionId),
      );
      final resultsOk = await _deleteResultCandidatesTrackingFailure(
        uid,
        sessionId,
      );
      if (!uploadOk || !resultsOk) anyObjectFailed = true;
    }

    return VirtualTryOnDataDeletionResult(
      outcome: anyObjectFailed
          ? VirtualTryOnDataDeletionOutcome.partial
          : VirtualTryOnDataDeletionOutcome.success,
      sessionsFound: snapshot.docs.length,
    );
  }

  /// `true` when [path] is confirmed gone - deleted just now, or already
  /// absent (an `object-not-found` failure is the expected common case, not
  /// a real failure). `false` only for a genuine failure (permission,
  /// network, etc.) - used where the caller needs an honest signal, unlike
  /// [_deleteUploadIgnoringErrors] elsewhere in this file, which is a
  /// deliberate fire-and-forget courtesy path with no caller depending on
  /// its outcome.
  Future<bool> _deleteObjectTrackingFailure(String path) async {
    try {
      await _storage.ref(path).delete();
      return true;
    } on FirebaseException catch (e) {
      return e.code == 'object-not-found';
    } catch (_) {
      return false;
    }
  }

  Future<bool> _deleteResultCandidatesTrackingFailure(
    String uid,
    String sessionId,
  ) async {
    var ok = true;
    for (final ext in const ['jpg', 'png']) {
      final deleted = await _deleteObjectTrackingFailure(
        'users/$uid/tryOnResults/$sessionId.$ext',
      );
      if (!deleted) ok = false;
    }
    return ok;
  }

  Future<void> _deleteUploadIgnoringErrors(String path) async {
    try {
      await _storage.ref(path).delete();
    } catch (_) {
      // Best-effort by design (D4 courtesy path) — the server's own
      // `generateTryOn` `finally` already deletes this for every call that
      // reached the function; a missing object here is the common case.
    }
  }

  Map<String, dynamic>? _asStringMap(Object? raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return null;
  }

  VirtualTryOnException _mapFunctionsException(FirebaseFunctionsException e) {
    final details = e.details;
    final appCode = details is Map ? details['appCode']?.toString() : null;
    final serverMsg = (e.message ?? '').trim();

    VirtualTryOnException of(VirtualTryOnErrorKind kind, String fallback) =>
        VirtualTryOnException(
          kind,
          serverMsg.isNotEmpty ? serverMsg : fallback,
        );

    switch (appCode) {
      case 'UNAUTHENTICATED':
        return of(
          VirtualTryOnErrorKind.notSignedIn,
          'Please sign in to use Virtual Try-On.',
        );
      case 'INVALID_REQUEST':
        return of(
          VirtualTryOnErrorKind.invalidRequest,
          'Something went wrong with that request. Please try again.',
        );
      case 'CONSENT_REQUIRED':
        return of(
          VirtualTryOnErrorKind.consentRequired,
          'Please confirm the Virtual Try-On consent before continuing.',
        );
      case 'PRODUCT_UNAVAILABLE':
        return of(
          VirtualTryOnErrorKind.productUnavailable,
          'This product is no longer available.',
        );
      case 'PRODUCT_NOT_ELIGIBLE':
        return of(
          VirtualTryOnErrorKind.productNotEligible,
          "Virtual Try-On isn't available for this product.",
        );
      case 'VARIANT_UNAVAILABLE':
        return of(
          VirtualTryOnErrorKind.variantUnavailable,
          "The selected colour or size isn't available for this product.",
        );
      case 'GARMENT_UNAVAILABLE':
        return of(
          VirtualTryOnErrorKind.garmentUnavailable,
          "A try-on image isn't configured for this colour yet.",
        );
      case 'FORBIDDEN':
        return of(
          VirtualTryOnErrorKind.forbidden,
          "You don't have access to this try-on session.",
        );
      case 'SESSION_ATTEMPT_CLOSED':
        return of(
          VirtualTryOnErrorKind.sessionAttemptClosed,
          'That try-on attempt has ended. Please start a new one.',
        );
      case 'SESSION_IN_PROGRESS':
        return of(
          VirtualTryOnErrorKind.sessionInProgress,
          'A preview is already being generated for this request. Please wait.',
        );
      case 'RATE_LIMITED':
        return of(
          VirtualTryOnErrorKind.rateLimited,
          "You've reached the try-on limit for now. Please try again later.",
        );
      case 'GLOBAL_LIMIT_REACHED':
        return of(
          VirtualTryOnErrorKind.globalLimitReached,
          'Virtual Try-On is at capacity right now. Please try again later.',
        );
      case 'PHOTO_MISSING':
        return of(
          VirtualTryOnErrorKind.photoMissing,
          "We couldn't find your photo. Please take or choose one and try again.",
        );
      case 'PHOTO_INVALID':
        return of(
          VirtualTryOnErrorKind.photoInvalid,
          "That photo couldn't be used. Please try a clear JPEG or PNG photo.",
        );
      case 'PROVIDER_UNAVAILABLE':
        return of(
          VirtualTryOnErrorKind.providerUnavailable,
          "We couldn't generate a preview right now. Please try again.",
        );
      case 'PROVIDER_REFUSED':
        return of(
          VirtualTryOnErrorKind.providerRefused,
          "We couldn't generate a preview for this photo. Please try a different photo.",
        );
      case 'TIMEOUT':
        return of(
          VirtualTryOnErrorKind.timeout,
          'Generating your preview took too long. Please try again.',
        );
      default:
        if (e.code == 'unavailable' || e.code == 'deadline-exceeded') {
          return const VirtualTryOnException.network();
        }
        return of(
          VirtualTryOnErrorKind.unknown,
          'Something went wrong generating your preview. Please try again.',
        );
    }
  }
}
