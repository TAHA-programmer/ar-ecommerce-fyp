import 'dart:async';
import 'dart:io';

import 'package:firebase_storage/firebase_storage.dart';

/// How a Storage fetch failed, classified so [RoomArModelService] can map to
/// the right customer-safe state (offline vs. genuine error) without ever
/// surfacing a raw `FirebaseException`. Mirrors
/// `FirebaseStorageService._mapError`'s convention.
enum RoomArModelStorageErrorKind {
  /// No connectivity / the request timed out or exhausted retries. The caller
  /// should prefer a cached copy and, failing that, show an offline state.
  offline,

  /// The object does not exist at that path.
  notFound,

  /// The object is larger than the caller's hard ceiling.
  tooLarge,

  /// The signed-in user is not allowed to read it (rules).
  permissionDenied,

  /// Anything else.
  unknown,
}

class RoomArModelStorageException implements Exception {
  const RoomArModelStorageException(this.kind, this.message);
  final RoomArModelStorageErrorKind kind;
  final String message;

  @override
  String toString() => 'RoomArModelStorageException($kind): $message';
}

/// Narrow port over "fetch a Storage object by its object path". Kept minimal
/// and purpose-fit (not a general file-transfer abstraction) so tests inject a
/// deterministic fake and the production path is the only place
/// `firebase_storage` is touched — the project's established
/// "interface + Firebase impl + test double" pattern (see
/// `storage_service.dart`).
abstract class RoomArModelStorageSource {
  /// The declared byte size of the object, from its metadata, or null when the
  /// backend does not report one.
  Future<int?> sizeOf(String storagePath);

  /// Streams the object at [storagePath] into [destination] (which the caller
  /// owns and will move/delete). Enforces [maxBytes] — both up-front against
  /// the metadata size and mid-transfer — and reports progress. Throws
  /// [RoomArModelStorageException] on any failure; [destination] may be left
  /// partially written and must be discarded by the caller.
  Future<void> downloadTo(
    String storagePath,
    File destination, {
    int? maxBytes,
    void Function(int received, int? total)? onProgress,
  });
}

/// Real Firebase Storage implementation. Always addresses the object by its
/// **Storage object path** — never a download URL, never a value read from
/// Firestore beyond the path itself (tracker §6 / 9.1b decision).
class FirebaseRoomArModelStorageSource implements RoomArModelStorageSource {
  FirebaseRoomArModelStorageSource({FirebaseStorage? storage})
    : _storageOverride = storage;

  final FirebaseStorage? _storageOverride;

  // Lazy for the same reason as `FirebaseStorageService._storage`: plain
  // `flutter test` runs never call `Firebase.initializeApp()`.
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  @override
  Future<int?> sizeOf(String storagePath) async {
    try {
      final meta = await _storage.ref(storagePath).getMetadata();
      return meta.size;
    } on FirebaseException catch (e) {
      throw _map(e);
    } on Object catch (e) {
      throw RoomArModelStorageException(
        RoomArModelStorageErrorKind.unknown,
        e.toString(),
      );
    }
  }

  @override
  Future<void> downloadTo(
    String storagePath,
    File destination, {
    int? maxBytes,
    void Function(int received, int? total)? onProgress,
  }) async {
    final ref = _storage.ref(storagePath);

    int? total;
    try {
      total = (await ref.getMetadata()).size;
    } on FirebaseException catch (e) {
      throw _map(e);
    } on Object {
      total = null; // size unknown up front; still guarded mid-transfer
    }
    if (maxBytes != null && total != null && total > maxBytes) {
      throw const RoomArModelStorageException(
        RoomArModelStorageErrorKind.tooLarge,
        'AR model object is larger than the allowed maximum.',
      );
    }

    final task = ref.writeToFile(destination);
    late final StreamSubscription<TaskSnapshot> sub;
    final completer = Completer<void>();
    sub = task.snapshotEvents.listen(
      (snap) {
        onProgress?.call(snap.bytesTransferred, total ?? snap.totalBytes);
        if (maxBytes != null && snap.bytesTransferred > maxBytes) {
          task.cancel();
        }
      },
      onError: (Object e) {
        if (!completer.isCompleted) completer.completeError(e);
      },
    );
    try {
      await task;
      if (!completer.isCompleted) completer.complete();
      await completer.future;
    } on FirebaseException catch (e) {
      if (e.code == 'canceled' && maxBytes != null) {
        throw const RoomArModelStorageException(
          RoomArModelStorageErrorKind.tooLarge,
          'AR model object exceeded the allowed maximum mid-download.',
        );
      }
      throw _map(e);
    } on RoomArModelStorageException {
      rethrow;
    } on Object catch (e) {
      throw RoomArModelStorageException(
        _looksOffline(e)
            ? RoomArModelStorageErrorKind.offline
            : RoomArModelStorageErrorKind.unknown,
        e.toString(),
      );
    } finally {
      await sub.cancel();
    }
  }

  RoomArModelStorageException _map(FirebaseException e) {
    switch (e.code) {
      case 'retry-limit-exceeded':
      case 'unknown':
        return RoomArModelStorageException(
          RoomArModelStorageErrorKind.offline,
          e.message ?? e.code,
        );
      case 'object-not-found':
        return RoomArModelStorageException(
          RoomArModelStorageErrorKind.notFound,
          e.message ?? e.code,
        );
      case 'unauthorized':
      case 'permission-denied':
        return RoomArModelStorageException(
          RoomArModelStorageErrorKind.permissionDenied,
          e.message ?? e.code,
        );
      default:
        return RoomArModelStorageException(
          RoomArModelStorageErrorKind.unknown,
          e.message ?? e.code,
        );
    }
  }

  bool _looksOffline(Object e) =>
      e is SocketException ||
      e is TimeoutException ||
      e.toString().toLowerCase().contains('network');
}
