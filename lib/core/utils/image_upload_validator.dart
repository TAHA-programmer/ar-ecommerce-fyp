import 'dart:io';

/// Thrown when a locally-picked image fails preflight validation, before any
/// Storage upload is attempted. Always carries a clean, user-facing message
/// - never a raw filesystem/platform exception - so callers can surface it
/// directly via `AppToast.error`, matching this project's established
/// `StorageServiceException`/`FirebaseAuthRepository._mapAuthError`
/// convention of never showing raw exception text.
class ImageValidationException implements Exception {
  final String message;
  const ImageValidationException(this.message);

  @override
  String toString() => message;
}

/// Mirrors `storage.rules`' `isValidImageType()` allow-list exactly.
const supportedImageExtensions = {'jpg', 'jpeg', 'png', 'webp'};

/// Mirrors `storage.rules`' `users/{uid}/profile/{imageId}` size limit.
const avatarMaxUploadBytes = 2 * 1024 * 1024;

/// Mirrors `storage.rules`' `products/{productId}/images/{imageId}` size
/// limit.
const productImageMaxUploadBytes = 10 * 1024 * 1024;

/// Mirrors `storage.rules`' `categories/{categoryId}/images/{imageId}` size
/// limit (Phase 8.8) - smaller than the product ceiling since a category
/// image is a single thumbnail, never a multi-image gallery.
const categoryImageMaxUploadBytes = 5 * 1024 * 1024;

/// Validates [file] is a real, existing, supported-type image at or under
/// [maxSizeBytes] BEFORE any Storage write is attempted.
///
/// `storage.rules` enforces the same content-type/size limits server-side -
/// this check does not replace that boundary, it exists so a bad local
/// selection fails fast and visibly (a clean `AppToast` via
/// [ImageValidationException]) instead of either silently doing nothing (an
/// oversized/unsupported file must never "look cancelled") or reaching the
/// network only to bounce off a raw `permission-denied`/`invalid-argument`
/// a user can't act on.
///
/// Deliberately does NOT use the lenient `extensionFromPath` helper (which
/// defaults unknown extensions to `jpg` for Storage object-naming purposes,
/// after a file has already been validated) - here an unrecognized
/// extension must be rejected, not silently coerced.
///
/// Deliberately uses the SYNCHRONOUS `dart:io` file APIs
/// (`existsSync`/`lengthSync`), not `exists`/`length`. This is not a style
/// choice: a locally-picked image's metadata is a trivial, fast filesystem
/// stat call, so the sync API's brief blocking cost is a non-issue - but
/// the async variants dispatch through `dart:io`'s native-port/event-loop
/// machinery, which silently never resolves when called from inside a
/// Flutter `testWidgets` body (its `FakeAsync`-driven test zone does not
/// pump real OS I/O completions the way plain `test()` bodies do), hanging
/// any such test until the framework's 10-minute per-test timeout fires.
/// The sync calls sidestep that failure mode entirely - this function stays
/// safely callable from every call site in this app, test or production,
/// with no special wrapping required.
Future<void> validateImageFileForUpload(
  File file, {
  required int maxSizeBytes,
  String label = 'image',
}) async {
  if (!file.existsSync()) {
    throw ImageValidationException(
      'Selected $label could not be found. Please try again.',
    );
  }

  final path = file.path;
  final dotIndex = path.lastIndexOf('.');
  final extension = (dotIndex == -1 || dotIndex == path.length - 1)
      ? ''
      : path.substring(dotIndex + 1).toLowerCase();
  if (!supportedImageExtensions.contains(extension)) {
    throw ImageValidationException(
      'Unsupported file type. Please choose a JPG, PNG, or WebP image.',
    );
  }

  final length = file.lengthSync();
  if (length > maxSizeBytes) {
    final maxMb = (maxSizeBytes / (1024 * 1024)).toStringAsFixed(0);
    throw ImageValidationException(
      'This $label is too large. Please choose one under ${maxMb}MB.',
    );
  }
}
