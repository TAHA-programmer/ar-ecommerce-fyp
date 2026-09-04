import 'dart:io';
import 'dart:typed_data';
import 'package:firebase_storage/firebase_storage.dart';
import 'storage_service.dart';

/// Real Firebase Storage implementation of [StorageService]. Never used
/// directly by tests - `MockStorageService` (test-only, in-memory) is
/// injected instead, mirroring `FirebaseAuthRepository`/
/// `FirestoreUserProfileRepository`'s split.
class FirebaseStorageService implements StorageService {
  final FirebaseStorage? _storageOverride;

  FirebaseStorageService({FirebaseStorage? storage})
    : _storageOverride = storage;

  /// Deliberately lazy - `FirebaseStorage.instance` throws immediately if no
  /// Firebase app has been initialized (e.g. every plain `flutter test` run
  /// that never calls `Firebase.initializeApp()`). Several ViewModels
  /// (`AdminProductFormViewModel`, `CustomerProfileState`) construct a real
  /// `FirebaseStorageService()` as their internal default via an optional
  /// constructor parameter - mirroring this codebase's established
  /// `AuthRepository?`/`OnboardingStore?` DI pattern - and are themselves
  /// constructed directly in many unit/widget tests that never touch
  /// Storage at all. Resolving `FirebaseStorage.instance` only when a
  /// method that actually needs it is called (not at construction time)
  /// means those tests never crash despite never providing a mock.
  FirebaseStorage get _storage => _storageOverride ?? FirebaseStorage.instance;

  @override
  Future<String> uploadProductImage({
    required String productId,
    required String objectName,
    required File file,
  }) async {
    final ref = _storage.ref('products/$productId/images/$objectName');
    try {
      await ref.putFile(file, _metadataFor(file.path));
    } on FirebaseException catch (e) {
      throw StorageServiceException(_mapError(e));
    } on Exception {
      throw const StorageServiceException(
        'Could not upload this image. Please try again.',
      );
    }

    try {
      return await ref.getDownloadURL();
    } on FirebaseException catch (e) {
      // The upload itself succeeded but we couldn't get a URL back for it -
      // the object now exists in Storage with nothing that will ever
      // reference it (no `ProductImageRef` was ever produced). Best-effort
      // delete it before failing, so a `getDownloadURL` hiccup never leaves
      // an untracked orphan behind for what the caller correctly sees as a
      // failed upload.
      try {
        await ref.delete();
      } catch (_) {
        // Best-effort only.
      }
      throw StorageServiceException(_mapError(e));
    } on Exception {
      try {
        await ref.delete();
      } catch (_) {
        // Best-effort only.
      }
      throw const StorageServiceException(
        'Could not upload this image. Please try again.',
      );
    }
  }

  @override
  Future<void> deleteProductImageByUrl(String downloadUrl) async {
    try {
      await _storage.refFromURL(downloadUrl).delete();
    } catch (_) {
      // Best-effort rollback only - see doc comment on the interface method.
      // A failure here never blocks or fails the caller's own operation.
    }
  }

  @override
  Future<String> uploadAvatar({
    required String uid,
    required String objectName,
    required File file,
  }) async {
    final path = 'users/$uid/profile/$objectName';
    final ref = _storage.ref(path);
    try {
      await ref.putFile(file, _metadataFor(file.path));
      // Deliberately returns the STORAGE PATH, never getDownloadURL() - see
      // StorageService.uploadAvatar's doc comment.
      return path;
    } on FirebaseException catch (e) {
      throw StorageServiceException(_mapError(e));
    } on Exception {
      throw const StorageServiceException(
        'Could not upload your photo. Please try again.',
      );
    }
  }

  @override
  Future<Uint8List> downloadAvatarBytes(
    String storagePath, {
    int maxSize = 2 * 1024 * 1024,
  }) async {
    try {
      final bytes = await _storage.ref(storagePath).getData(maxSize);
      if (bytes == null) {
        throw const StorageServiceException('Avatar image not found.');
      }
      return bytes;
    } on FirebaseException catch (e) {
      throw StorageServiceException(_mapError(e));
    }
  }

  @override
  Future<void> deleteAvatarByPath(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
    } catch (_) {
      // Best-effort only - see doc comment on the interface method.
    }
  }

  @override
  Future<String> uploadCategoryImage({
    required String categoryId,
    required String objectName,
    required File file,
  }) async {
    final ref = _storage.ref('categories/$categoryId/images/$objectName');
    try {
      await ref.putFile(file, _metadataFor(file.path));
    } on FirebaseException catch (e) {
      throw StorageServiceException(_mapError(e));
    } on Exception {
      throw const StorageServiceException(
        'Could not upload this image. Please try again.',
      );
    }

    try {
      // getDownloadURL() returns a persistent, non-expiring Firebase media
      // URL (with a download token, not a time-limited GCS signed URL) -
      // directly usable by Image.network, exactly like uploadProductImage.
      return await ref.getDownloadURL();
    } on FirebaseException catch (e) {
      // Same orphan-prevention as uploadProductImage: the upload itself
      // succeeded but no ProductImageRef/CommerceCategoryModel will ever
      // reference this object if we can't get a URL back for it - best-effort
      // delete it before failing.
      try {
        await ref.delete();
      } catch (_) {
        // Best-effort only.
      }
      throw StorageServiceException(_mapError(e));
    } on Exception {
      try {
        await ref.delete();
      } catch (_) {
        // Best-effort only.
      }
      throw const StorageServiceException(
        'Could not upload this image. Please try again.',
      );
    }
  }

  @override
  Future<void> deleteCategoryImageByUrl(String downloadUrl) async {
    try {
      await _storage.refFromURL(downloadUrl).delete();
    } catch (_) {
      // Best-effort rollback only - see doc comment on the interface method.
    }
  }

  // ── Phase 9.2 R16 — Admin Room-AR GLB model ────────────────────────────

  @override
  Future<String> uploadArModel({
    required String productId,
    required String objectName,
    required File file,
    Map<String, String>? provenance,
    void Function(double progress)? onProgress,
  }) async {
    final path = 'products/$productId/ar/$objectName';
    final ref = _storage.ref(path);
    final metadata = SettableMetadata(
      contentType: 'model/gltf-binary',
      // Every version has a distinct object name, so its bytes are immutable
      // under that path - matches `scripts/upload_ar_models/` and lets the
      // on-device cache trust a path+version key.
      cacheControl: 'public, max-age=31536000, immutable',
      // `twinArAr*` provenance — byte-identical in shape to what the R10
      // Admin-SDK upload tool writes; `storage.rules` requires the SHA key.
      customMetadata: provenance,
    );
    try {
      final task = ref.putFile(file, metadata);
      final progressSub = task.snapshotEvents.listen(
        (s) {
          if (onProgress != null && s.totalBytes > 0) {
            onProgress((s.bytesTransferred / s.totalBytes).clamp(0.0, 1.0));
          }
        },
        onError: (_) {
          // The awaited task below surfaces the real failure; this listener
          // only exists for progress and must not throw on its own.
        },
      );
      try {
        await task;
      } finally {
        await progressSub.cancel();
      }
      // Deliberately returns the STORAGE OBJECT PATH, never getDownloadURL() -
      // see StorageService.uploadArModel's doc comment.
      return path;
    } on FirebaseException catch (e) {
      await _bestEffortDelete(ref);
      throw StorageServiceException(_mapError(e));
    } on Exception {
      await _bestEffortDelete(ref);
      throw const StorageServiceException(
        'Could not upload this 3D model. Please try again.',
      );
    }
  }

  @override
  Future<Uint8List> downloadArModelBytes(
    String storagePath, {
    int maxSize = 16 * 1024 * 1024,
  }) async {
    try {
      final bytes = await _storage.ref(storagePath).getData(maxSize);
      if (bytes == null) {
        throw const StorageServiceException('3D model not found.');
      }
      return bytes;
    } on FirebaseException catch (e) {
      throw StorageServiceException(_mapError(e));
    }
  }

  @override
  Future<bool> deleteArModelByPath(String storagePath) async {
    try {
      await _storage.ref(storagePath).delete();
      return true;
    } on FirebaseException catch (e) {
      // An object that is already gone is a success for the caller's intent.
      return e.code == 'object-not-found';
    } catch (_) {
      return false;
    }
  }

  Future<void> _bestEffortDelete(Reference ref) async {
    try {
      await ref.delete();
    } catch (_) {
      // Best-effort only.
    }
  }

  SettableMetadata _metadataFor(String localPath) {
    final lower = localPath.toLowerCase();
    String contentType = 'image/jpeg';
    if (lower.endsWith('.png')) {
      contentType = 'image/png';
    } else if (lower.endsWith('.webp')) {
      contentType = 'image/webp';
    }
    return SettableMetadata(contentType: contentType);
  }

  /// Never surfaces raw Firebase exception text - matches this project's
  /// established `FirebaseAuthRepository._mapAuthError` convention.
  String _mapError(FirebaseException e) {
    switch (e.code) {
      case 'unauthorized':
      case 'permission-denied':
        return 'You do not have permission to do that.';
      case 'canceled':
        return 'Upload cancelled.';
      case 'retry-limit-exceeded':
      case 'unknown':
        return 'Network error. Please check your connection and try again.';
      case 'object-not-found':
        return 'Image not found.';
      case 'quota-exceeded':
        return 'Storage limit reached. Please try again later.';
      default:
        return 'Something went wrong. Please try again.';
    }
  }
}
