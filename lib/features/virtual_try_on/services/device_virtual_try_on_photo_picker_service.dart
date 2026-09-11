import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';

import 'virtual_try_on_photo_picker_service.dart';

/// Real [VirtualTryOnPhotoPickerService]: `image_picker`, camera source
/// pinned to [CameraDevice.rear] (Stage 5 approved decision — Option A: no
/// `camera` plugin, no in-app front-camera affordance; the OS camera app's
/// own flip control, if any, is outside this app's control and is disclosed
/// as a known limitation rather than silently overclaimed).
///
/// No `maxWidth`/`maxHeight`/`imageQuality` is requested here — this flow
/// always independently decodes + re-encodes via `PersonPhotoProcessor`
/// before upload, so relying on `image_picker`'s own (platform-version
/// dependent) compression would be redundant and, for a picked PNG, is not
/// guaranteed to produce JPEG bytes at all.
class DeviceVirtualTryOnPhotoPickerService
    implements VirtualTryOnPhotoPickerService {
  final ImagePicker _picker;

  DeviceVirtualTryOnPhotoPickerService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  @override
  Future<Uint8List?> captureFromCamera() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.rear,
      );
      if (image == null) return null;
      return await image.readAsBytes();
    } catch (_) {
      return null;
    }
  }

  @override
  Future<Uint8List?> pickFromGallery() async {
    try {
      final image = await _picker.pickImage(source: ImageSource.gallery);
      if (image == null) return null;
      return await image.readAsBytes();
    } catch (_) {
      return null;
    }
  }
}
