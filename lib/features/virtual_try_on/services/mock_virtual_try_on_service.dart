import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import 'virtual_try_on_exception.dart';
import 'virtual_try_on_service.dart';

/// Fully-controllable [VirtualTryOnService] for tests and previews — no real
/// Firebase call, mirrors [FirebaseVirtualTryOnService]'s session-id
/// algorithm exactly so tests can assert the real upload/session path shape.
class MockVirtualTryOnService implements VirtualTryOnService {
  /// When set, [uploadPersonPhoto] awaits this before completing — lets a
  /// test hold the "uploading" phase open to exercise cancel-during-upload.
  Completer<void>? uploadGate;

  /// Set to make the next [uploadPersonPhoto] call throw this instead.
  VirtualTryOnException? nextUploadError;

  /// Set to make the next [generate] call throw this instead of succeeding.
  VirtualTryOnException? nextGenerateError;

  /// When set, [generate] awaits this before completing — lets a test hold
  /// the "generating" phase open (e.g. to exercise the "leave while
  /// generating?" confirmation).
  Completer<void>? generateGate;

  /// Overrides the successful [generate] result builder.
  VirtualTryOnGenerateResult Function(String sessionId)? generateResultBuilder;

  /// Bytes returned by [downloadResult].
  Uint8List downloadBytes = Uint8List.fromList(const [1, 2, 3]);

  VirtualTryOnException? nextDownloadError;

  final List<String> uploadCalls = [];
  final List<String> generateCalls = [];
  final List<String> deletedUploadSessionIds = [];
  final List<String> deletedResultPaths = [];
  int deleteAllTryOnDataCalls = 0;

  /// Overrides the result [deleteAllTryOnData] returns.
  VirtualTryOnDataDeletionResult deleteAllTryOnDataResult =
      const VirtualTryOnDataDeletionResult(
        outcome: VirtualTryOnDataDeletionOutcome.success,
        sessionsFound: 0,
      );

  @override
  String deriveSessionId({
    required String uid,
    required String idempotencyKey,
  }) {
    return sha256.convert(utf8.encode('$uid $idempotencyKey')).toString();
  }

  @override
  Future<void> uploadPersonPhoto({
    required String uid,
    required String idempotencyKey,
    required Uint8List personPhotoJpegBytes,
  }) async {
    uploadCalls.add(idempotencyKey);
    final gate = uploadGate;
    if (gate != null) await gate.future;
    final error = nextUploadError;
    if (error != null) throw error;
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
    generateCalls.add(idempotencyKey);
    final gate = generateGate;
    if (gate != null) await gate.future;

    if (!consent) {
      throw const VirtualTryOnException(
        VirtualTryOnErrorKind.consentRequired,
        'Please confirm the Virtual Try-On consent before continuing.',
      );
    }

    final error = nextGenerateError;
    if (error != null) {
      deletedUploadSessionIds.add(sessionId);
      throw error;
    }

    final builder = generateResultBuilder;
    if (builder != null) return builder(sessionId);

    return VirtualTryOnGenerateResult(
      sessionId: sessionId,
      resultPath: 'users/$uid/tryOnResults/$sessionId.jpg',
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
      provider: 'gemini',
      providerModel: 'gemini-2.5-flash-image',
    );
  }

  @override
  Future<Uint8List> downloadResult(
    String resultPath, {
    int maxSize = 15 * 1024 * 1024,
  }) async {
    final error = nextDownloadError;
    if (error != null) throw error;
    return downloadBytes;
  }

  @override
  Future<void> deleteUploadBestEffort({
    required String uid,
    required String idempotencyKey,
  }) async {
    deletedUploadSessionIds.add(
      deriveSessionId(uid: uid, idempotencyKey: idempotencyKey),
    );
  }

  @override
  Future<void> deleteResultBestEffort(String resultPath) async {
    deletedResultPaths.add(resultPath);
  }

  @override
  Future<VirtualTryOnDataDeletionResult> deleteAllTryOnData({
    required String uid,
  }) async {
    deleteAllTryOnDataCalls++;
    return deleteAllTryOnDataResult;
  }
}
