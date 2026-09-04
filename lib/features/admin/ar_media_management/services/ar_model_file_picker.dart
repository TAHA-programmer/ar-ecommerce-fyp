import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/admin_glb_validator.dart' show kArModelTransportMaxBytes;

/// Narrow seam over the platform document picker so the Admin AR & Media
/// ViewModel stays unit-testable (a fake picker returns a temp `.glb`), and so
/// the one `file_picker` call site in the app is isolated. Mirrors this
/// project's `StorageService` / `AuthRepository` interface-plus-impl pattern.
abstract class ArModelFilePicker {
  /// Opens the platform picker filtered to `.glb` and returns the picked file
  /// as a real on-disk [File] (copying it out of a `content://` URI into the
  /// cache directory when the platform doesn't expose a direct path). Returns
  /// `null` when the admin cancels. Throws [ArModelFilePickException] with
  /// clean text on a picker/plugin error.
  Future<File?> pickGlb();
}

class ArModelFilePickException implements Exception {
  final String message;
  const ArModelFilePickException(this.message);

  @override
  String toString() => message;
}

class FilePickerArModelFilePicker implements ArModelFilePicker {
  const FilePickerArModelFilePicker();

  @override
  Future<File?> pickGlb() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['glb'],
      );
    } on Exception {
      throw const ArModelFilePickException(
        'Could not open the file picker. Please try again.',
      );
    }
    if (picked == null) return null;

    // Reject an oversized selection from its declared length BEFORE any bytes
    // are read into memory — `PlatformFile.length()` is a cheap stat, not a
    // read. The transport ceiling is used here (the strict authoring budget is
    // re-checked from the bytes by `inspectArGlbFile`); this guard only exists
    // so a multi-hundred-MB pick can never be slurped into RAM first.
    try {
      final declaredLength = await picked.length();
      if (declaredLength > kArModelTransportMaxBytes) {
        final mb = (declaredLength / (1024 * 1024)).toStringAsFixed(1);
        throw ArModelFilePickException(
          'That file is $mb MB — far larger than any 3D model should be. '
          'Choose a smaller .glb.',
        );
      }
    } on ArModelFilePickException {
      rethrow;
    } on Exception {
      // `length()` failing is not fatal — `inspectArGlbFile` re-checks size
      // from disk after (bounded) materialisation below.
    }

    // A direct filesystem path when the platform exposes one …
    final directPath = picked.path;
    if (directPath != null && File(directPath).existsSync()) {
      return File(directPath);
    }

    // … otherwise materialise the bytes into a cache file we control.
    try {
      final bytes = await picked.readAsBytes();
      final dir = await getApplicationCacheDirectory();
      final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final out = File(
        '${dir.path}/ar_model_pick_'
        '${DateTime.now().microsecondsSinceEpoch}_$safeName',
      );
      await out.writeAsBytes(bytes, flush: true);
      return out;
    } on Exception {
      throw const ArModelFilePickException(
        'Could not read the selected file. Please choose it again.',
      );
    }
  }
}
