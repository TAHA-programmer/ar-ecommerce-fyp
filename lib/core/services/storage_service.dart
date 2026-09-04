import 'dart:io';
import 'dart:typed_data';

/// Abstraction over Firebase Storage, mirroring `AuthRepository`/
/// `CommerceDatabase`'s established "abstract interface + real Firebase
/// implementation + test double" pattern (see `firebase_storage_service.dart`
/// and `mock_storage_service.dart`). Kept as one narrow interface, not a
/// generic file-storage abstraction, since product-image and avatar storage
/// have genuinely different security shapes (public vs. owner-only) and this
/// project's rule ("do NOT introduce Clean Architecture/use-case layers")
/// favors a small, purpose-fit interface over a speculative general one.
abstract class StorageService {
  /// Uploads [file] to `products/{productId}/images/{objectName}` and
  /// returns its public download URL - product images are public-read (see
  /// `storage.rules`), so a plain download URL is the correct, simplest
  /// representation for `ProductImageRef(source: .network)`.
  Future<String> uploadProductImage({
    required String productId,
    required String objectName,
    required File file,
  });

  /// Deletes a product image previously uploaded by [uploadProductImage],
  /// identified by the exact download URL it returned. Used ONLY for
  /// same-save rollback of a just-uploaded file when the following Firestore
  /// write fails - never for deleting a previously committed product image
  /// (historical `OrderItemModel` snapshots may still reference it; see
  /// `AdminProductFormViewModel`'s doc comment on this).
  Future<void> deleteProductImageByUrl(String downloadUrl);

  /// Uploads [file] to `users/{uid}/profile/{objectName}` and returns the
  /// Storage OBJECT PATH (e.g. `users/abc123/profile/171234_ab12.jpg`) -
  /// deliberately NEVER a download URL or token. Avatars are owner+admin
  /// read-only (see `storage.rules`), so the app must always fetch them
  /// through an authenticated call, never a bare public URL.
  Future<String> uploadAvatar({
    required String uid,
    required String objectName,
    required File file,
  });

  /// Fetches the raw bytes of an avatar at [storagePath] via an
  /// authenticated Storage read (`ref.getData(maxSize)`), enforcing that the
  /// signed-in caller may only ever successfully read their own avatar or,
  /// if a superAdmin, any avatar - matching `storage.rules`. [maxSize] is a
  /// client-side guard against loading an unexpectedly huge object into
  /// memory; it does not need to match the write-time size limit exactly.
  Future<Uint8List> downloadAvatarBytes(String storagePath, {int maxSize});

  /// Deletes the avatar at [storagePath]. Used for best-effort cleanup of a
  /// user's previous avatar object after a successful re-upload, and for
  /// rollback of a just-uploaded avatar if the following Firestore write
  /// fails. Never fatal to the caller if it fails - see call sites.
  Future<void> deleteAvatarByPath(String storagePath);

  /// Uploads [file] to `categories/{categoryId}/images/{objectName}` and
  /// returns a persistent, non-expiring public download URL (Phase 8.8 -
  /// category images are public-read, mirroring product images, per
  /// `storage.rules`) - suitable for direct `Image.network` use, exactly
  /// like [uploadProductImage]. Deliberately never a fixed `image.{ext}`
  /// object name (unlike the avatar's single-well-known-slot design): a
  /// content-addressed/unique object name means a Firestore-write failure
  /// after a successful upload can be rolled back by deleting exactly that
  /// one new object, without any risk of deleting a still-referenced
  /// previous image if the two happen to share a name.
  Future<String> uploadCategoryImage({
    required String categoryId,
    required String objectName,
    required File file,
  });

  /// Deletes a category image previously uploaded by [uploadCategoryImage],
  /// identified by the exact download URL it returned. Used for same-save
  /// rollback of a just-uploaded file when the following Firestore write
  /// fails, and for best-effort cleanup of the previous image after a
  /// successful replace. Never fatal to the caller if it fails.
  Future<void> deleteCategoryImageByUrl(String downloadUrl);

  // ── Phase 9.2 R16 — Admin Room-AR GLB model ────────────────────────────

  /// Uploads a Room-AR GLB [file] to `products/{productId}/ar/{objectName}`
  /// and returns the Storage **object path** (e.g.
  /// `products/luna-accent-chair/ar/model-v2.glb`) — deliberately NEVER a
  /// download URL, matching [ProductArMetadata.storagePath] and the way
  /// `RoomArModelService` fetches (by object path only). [objectName] MUST be
  /// `model-v{n}.glb`; the caller owns version selection. Content type is set
  /// to `model/gltf-binary` and an immutable cache-control (every version has
  /// a distinct object name, so the bytes never change under a path).
  /// [onProgress] receives 0.0–1.0 as the transfer proceeds.
  ///
  /// [provenance] — the `twinArAr*` custom-metadata (SHA-256 / version /
  /// dimensions / scale-contract), byte-identical in shape to what
  /// `scripts/upload_ar_models/` writes, so every AR object (Admin-app or
  /// Admin-SDK tool) carries verifiable provenance and `storage.rules` can
  /// require it.
  ///
  /// On any failure throws [StorageServiceException] with clean text; a
  /// half-written object left by a mid-transfer failure is best-effort
  /// deleted before the throw, so a failed upload never orphans bytes.
  Future<String> uploadArModel({
    required String productId,
    required String objectName,
    required File file,
    Map<String, String>? provenance,
    void Function(double progress)? onProgress,
  });

  /// Reads the exact bytes of the committed AR model at [storagePath] through
  /// an authenticated Storage call (`ref.getData(maxSize)`). Used to
  /// re-verify an already-committed model (SHA-256 + structure) and to feed
  /// the admin 3D preview. [maxSize] guards against loading an unexpectedly
  /// huge object into memory; it need not match the write-time ceiling.
  Future<Uint8List> downloadArModelBytes(String storagePath, {int maxSize});

  /// Deletes the AR model object at [storagePath]. Two callers only:
  ///  * best-effort rollback of a just-uploaded object when the subsequent
  ///    Firestore write fails (never fatal to the caller);
  ///  * the explicit, confirmed admin "permanently delete model data"
  ///    workflow.
  /// A previously-committed model that a *live* customer experience still
  /// points at is never passed here — the admin flow disables the entry
  /// point first.
  ///
  /// Returns `true` when the object is gone (deleted, or was already absent),
  /// `false` when the delete genuinely failed and the object may still exist.
  /// The rollback caller ignores the result; the explicit-delete caller
  /// surfaces an honest "file could not be removed — may need manual cleanup"
  /// note when it is `false`.
  Future<bool> deleteArModelByPath(String storagePath);
}

/// Thrown by [StorageService] implementations for user-facing failure
/// classification (permission/network/cancellation/etc.), so callers can map
/// to a clean `AppToast` message without ever surfacing a raw platform
/// exception - mirrors `FirebaseAuthRepository._mapAuthError`'s convention.
class StorageServiceException implements Exception {
  final String message;
  const StorageServiceException(this.message);

  @override
  String toString() => message;
}
