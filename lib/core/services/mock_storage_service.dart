import 'dart:io';
import 'dart:typed_data';
import 'storage_service.dart';

/// In-memory test double for [StorageService], mirroring
/// `MockUserProfileRepository`/`MockCommerceDatabase`'s role in this
/// codebase. Not used in production. Deliberately does not touch the real
/// filesystem or network - `uploadProductImage`/`uploadAvatar` fabricate a
/// stable, deterministic "URL"/"path" from the inputs so ViewModel-level
/// tests can assert on upload lifecycle (rollback, ordering, primary-image
/// tracking) without any real I/O.
class MockStorageService implements StorageService {
  final List<String> uploadedProductImageUrls = [];
  final List<String> deletedProductImageUrls = [];
  final List<String> uploadedAvatarPaths = [];
  final List<String> deletedAvatarPaths = [];

  /// When set, every `uploadProductImage` call throws this instead of
  /// succeeding - used to test the whole-batch-upload-failure/rollback path.
  Object? failUploadProductImageWith;

  /// When set, only the Nth call (1-indexed) to `uploadProductImage` throws
  /// [failProductImageUploadOnCallWith] - the rest succeed normally. Used to
  /// test a PARTIAL-batch failure (e.g. image 1 of 2 uploads successfully,
  /// image 2 fails), distinct from [failUploadProductImageWith] which fails
  /// every call including the first.
  int? failProductImageUploadOnCallNumber;
  Object failProductImageUploadOnCallWith = const StorageServiceException(
    'simulated partial-batch failure',
  );

  /// When set, every `uploadAvatar` call throws this.
  Object? failUploadAvatarWith;

  /// When set, `downloadAvatarBytes` throws this instead of returning bytes.
  Object? failDownloadAvatarWith;

  /// When set, every `uploadCategoryImage` call throws this instead of
  /// succeeding.
  Object? failUploadCategoryImageWith;

  final List<String> uploadedCategoryImageUrls = [];
  final List<String> deletedCategoryImageUrls = [];

  int _uploadCallCount = 0;
  int _productImageUploadCallCount = 0;

  @override
  Future<String> uploadProductImage({
    required String productId,
    required String objectName,
    required File file,
  }) async {
    _productImageUploadCallCount++;
    if (failUploadProductImageWith != null) {
      throw failUploadProductImageWith!;
    }
    if (failProductImageUploadOnCallNumber == _productImageUploadCallCount) {
      throw failProductImageUploadOnCallWith;
    }
    _uploadCallCount++;
    final url =
        'https://mock-storage.test/products/$productId/images/$objectName';
    uploadedProductImageUrls.add(url);
    return url;
  }

  @override
  Future<void> deleteProductImageByUrl(String downloadUrl) async {
    deletedProductImageUrls.add(downloadUrl);
  }

  @override
  Future<String> uploadAvatar({
    required String uid,
    required String objectName,
    required File file,
  }) async {
    if (failUploadAvatarWith != null) {
      throw failUploadAvatarWith!;
    }
    _uploadCallCount++;
    final path = 'users/$uid/profile/$objectName';
    uploadedAvatarPaths.add(path);
    return path;
  }

  @override
  Future<Uint8List> downloadAvatarBytes(
    String storagePath, {
    int maxSize = 2 * 1024 * 1024,
  }) async {
    if (failDownloadAvatarWith != null) {
      throw failDownloadAvatarWith!;
    }
    return Uint8List.fromList([1, 2, 3, 4]);
  }

  @override
  Future<void> deleteAvatarByPath(String storagePath) async {
    deletedAvatarPaths.add(storagePath);
  }

  @override
  Future<String> uploadCategoryImage({
    required String categoryId,
    required String objectName,
    required File file,
  }) async {
    if (failUploadCategoryImageWith != null) {
      throw failUploadCategoryImageWith!;
    }
    _uploadCallCount++;
    final url =
        'https://mock-storage.test/categories/$categoryId/images/$objectName';
    uploadedCategoryImageUrls.add(url);
    return url;
  }

  @override
  Future<void> deleteCategoryImageByUrl(String downloadUrl) async {
    deletedCategoryImageUrls.add(downloadUrl);
  }

  // ── Phase 9.2 R16 — Admin Room-AR GLB model ────────────────────────────

  /// Records `products/{productId}/ar/{objectName}` object paths uploaded.
  final List<String> uploadedArModelPaths = [];
  final List<String> deletedArModelPaths = [];

  /// When set, every `uploadArModel` call throws this instead of succeeding.
  Object? failUploadArModelWith;

  /// When set, `downloadArModelBytes` throws this instead of returning bytes.
  Object? failDownloadArModelWith;

  /// When true, `deleteArModelByPath` records the path but returns `false`
  /// (the object could not be removed) — for testing the honest
  /// "may need manual cleanup" note.
  bool failDeleteArModel = false;

  /// The `provenance` custom-metadata passed to the most recent
  /// `uploadArModel` (or `null` if none was passed).
  Map<String, String>? lastArModelProvenance;

  /// Bytes handed back by `downloadArModelBytes` (per storagePath, then a
  /// default). Lets a viewmodel test drive the re-verify path deterministically.
  final Map<String, Uint8List> arModelBytesByPath = {};
  Uint8List arModelBytesDefault = Uint8List.fromList([1, 2, 3, 4]);

  @override
  Future<String> uploadArModel({
    required String productId,
    required String objectName,
    required File file,
    Map<String, String>? provenance,
    void Function(double progress)? onProgress,
  }) async {
    if (failUploadArModelWith != null) throw failUploadArModelWith!;
    _uploadCallCount++;
    lastArModelProvenance = provenance;
    onProgress?.call(0.5);
    onProgress?.call(1.0);
    final path = 'products/$productId/ar/$objectName';
    uploadedArModelPaths.add(path);
    // Remember the exact bytes so `downloadArModelBytes` round-trips them —
    // the ViewModel re-verifies (structure + bbox + SHA-256) what it just
    // uploaded, and a test should not have to pre-seed that separately.
    try {
      arModelBytesByPath[path] = file.readAsBytesSync();
    } catch (_) {
      // A test may pass a non-existent file path; leave the default bytes.
    }
    return path;
  }

  @override
  Future<Uint8List> downloadArModelBytes(
    String storagePath, {
    int maxSize = 16 * 1024 * 1024,
  }) async {
    if (failDownloadArModelWith != null) throw failDownloadArModelWith!;
    return arModelBytesByPath[storagePath] ?? arModelBytesDefault;
  }

  @override
  Future<bool> deleteArModelByPath(String storagePath) async {
    deletedArModelPaths.add(storagePath);
    return !failDeleteArModel;
  }

  /// Total number of successful uploads (product images + avatars)
  /// performed so far - convenience for tests asserting "only the new file
  /// was uploaded, not the whole gallery".
  int get uploadCallCount => _uploadCallCount;
}
