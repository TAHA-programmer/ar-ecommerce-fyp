import 'dart:io';
import 'dart:typed_data';

/// Test-only helper for creating real, on-disk files that
/// `validateImageFileForUpload`'s filesystem-backed preflight checks
/// (existence, extension, byte size) can actually see. Every test that
/// exercises an upload path through real preflight validation must use a
/// real file - a fabricated path like `File('local/photo.jpg')` (used
/// before preflight validation existed) now correctly fails the
/// existence check, so tests need genuine temporary files instead.
///
/// Deliberately uses the SYNCHRONOUS `dart:io` APIs throughout
/// (`createTempSync`/`writeAsBytesSync`/`existsSync`/`deleteSync`), not
/// their async counterparts. This is required, not a style preference: the
/// async variants dispatch through `dart:io`'s native-port/event-loop
/// machinery, which silently never resolves when called from inside a
/// Flutter `testWidgets` body (its `FakeAsync`-driven test zone does not
/// pump real OS I/O completions) - `admin_product_form_image_upload_test
/// .dart` hit exactly this as a genuine 10-minute test hang before this
/// helper was switched to sync calls. Sync filesystem calls run inline on
/// the calling thread with no event-loop dependency, so this helper is
/// safely callable from both plain `test()` bodies and `testWidgets()`
/// bodies alike, with no special wrapping required at any call site.
///
/// Callers are responsible for cleanup via [cleanUp] (or letting the OS
/// temp directory reap them) - `tearDown` in each test file handles this
/// centrally.
class TestImageFile {
  static final List<Directory> _tempDirs = [];

  /// Creates a real temporary file with a JPEG magic-number prefix (never
  /// decoded, but shaped realistically) and [sizeBytes] total length, named
  /// with the given [extension]. Defaults to a small, valid (well under
  /// every limit in this app) file - pass a specific [sizeBytes] to test
  /// the oversized-rejection path, or an unsupported [extension] to test
  /// the unsupported-type-rejection path.
  static Future<File> create({
    String extension = 'jpg',
    int sizeBytes = 1024,
  }) async {
    final dir = Directory.systemTemp.createTempSync('twin_ar_test_image_');
    _tempDirs.add(dir);
    final file = File('${dir.path}/test_image.$extension');
    final bytes = Uint8List(sizeBytes < 4 ? 4 : sizeBytes);
    // JPEG magic number - not required by any check in this app (which
    // only inspects extension/size), but keeps the fixture honest.
    bytes[0] = 0xFF;
    bytes[1] = 0xD8;
    bytes[2] = 0xFF;
    bytes[3] = 0xE0;
    file.writeAsBytesSync(sizeBytes < 4 ? bytes.sublist(0, 4) : bytes);
    return file;
  }

  /// Deletes every temp directory created by [create] so far in this test
  /// process. Safe to call even if nothing was ever created, and safe to
  /// call multiple times.
  static Future<void> cleanUp() async {
    for (final dir in _tempDirs) {
      try {
        if (dir.existsSync()) {
          dir.deleteSync(recursive: true);
        }
      } catch (_) {
        // Best-effort only - stray temp files are not a test failure.
      }
    }
    _tempDirs.clear();
  }
}
