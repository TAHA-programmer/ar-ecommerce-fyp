import 'dart:typed_data';

import 'virtual_try_on_photo_picker_service.dart';

/// Fully-controllable [VirtualTryOnPhotoPickerService] for tests — no real
/// platform channel.
class MockVirtualTryOnPhotoPickerService
    implements VirtualTryOnPhotoPickerService {
  Uint8List? nextCameraResult;
  Uint8List? nextGalleryResult;
  int captureFromCameraCalls = 0;
  int pickFromGalleryCalls = 0;

  @override
  Future<Uint8List?> captureFromCamera() async {
    captureFromCameraCalls++;
    return nextCameraResult;
  }

  @override
  Future<Uint8List?> pickFromGallery() async {
    pickFromGalleryCalls++;
    return nextGalleryResult;
  }
}
