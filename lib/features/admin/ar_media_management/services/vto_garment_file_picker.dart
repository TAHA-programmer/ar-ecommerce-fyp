import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/admin_vto_garment_validator.dart'
    show kVtoGarmentTransportMaxBytes;

/// Narrow seam over the platform document picker so the Admin AR & Media
/// ViewModel stays unit-testable (a fake picker returns a temp image), and so
/// the `file_picker` call sites stay isolated. Exact shape of
/// [ArModelFilePicker] in the same feature — mirrors this project's
/// interface-plus-impl DI pattern.
abstract class VtoGarmentFilePicker {
  /// Opens the platform picker filtered to JPEG/PNG and returns the picked file
  /// as a real on-disk [File], copying it out of a `content://` URI into a
  /// cache file the app owns when the platform exposes no direct path
  /// (**raw bytes preserved** — required for the signature check + SHA-256).
  /// Returns `null` when the admin cancels. Throws [VtoGarmentFilePickException]
  /// with clean text on a picker/plugin error or an obviously-oversized pick.
  Future<File?> pickImage();
}

class VtoGarmentFilePickException implements Exception {
  final String message;
  const VtoGarmentFilePickException(this.message);

  @override
  String toString() => message;
}

class FilePickerVtoGarmentFilePicker implements VtoGarmentFilePicker {
  const FilePickerVtoGarmentFilePicker();

  @override
  Future<File?> pickImage() async {
    final PlatformFile? picked;
    try {
      picked = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: const ['jpg', 'jpeg', 'png'],
      );
    } on Exception {
      throw const VtoGarmentFilePickException(
        'Could not open the file picker. Please try again.',
      );
    }
    if (picked == null) return null;

    // Reject an obviously-oversized selection from its declared length BEFORE
    // any bytes are read into memory — `PlatformFile.length()` is a cheap stat,
    // not a read. The transport ceiling is used here (the stricter 8 MiB
    // authoring budget is re-checked from the bytes by `inspectVtoGarmentFile`);
    // this guard only exists so a huge pick can never be slurped into RAM.
    try {
      final declaredLength = await picked.length();
      if (declaredLength > kVtoGarmentTransportMaxBytes) {
        final mb = (declaredLength / (1024 * 1024)).toStringAsFixed(1);
        throw VtoGarmentFilePickException(
          'That file is $mb MB — far larger than a garment image should be. '
          'Choose a smaller JPEG or PNG.',
        );
      }
    } on VtoGarmentFilePickException {
      rethrow;
    } on Exception {
      // `length()` failing is not fatal — `inspectVtoGarmentFile` re-checks
      // size from disk after (bounded) materialisation below.
    }

    // A direct filesystem path when the platform exposes one …
    final directPath = picked.path;
    if (directPath != null && File(directPath).existsSync()) {
      return File(directPath);
    }

    // … otherwise materialise the exact bytes into a cache file we control.
    try {
      final bytes = await picked.readAsBytes();
      final dir = await getApplicationCacheDirectory();
      final safeName = picked.name.replaceAll(RegExp(r'[^A-Za-z0-9._-]'), '_');
      final out = File(
        '${dir.path}/vto_garment_pick_'
        '${DateTime.now().microsecondsSinceEpoch}_$safeName',
      );
      await out.writeAsBytes(bytes, flush: true);
      return out;
    } on Exception {
      throw const VtoGarmentFilePickException(
        'Could not read the selected file. Please choose it again.',
      );
    }
  }
}
