import 'dart:typed_data';

/// Abstraction over picking a Virtual Try-On person photo (Phase 9.3 Stage 5)
/// — a narrower, VTO-specific sibling of [ImagePickerService] that returns
/// raw bytes directly (this flow always re-encodes via
/// `PersonPhotoProcessor` before upload, so a file path is never needed) and
/// makes the rear-camera preference explicit at the call site rather than
/// relying on `image_picker`'s own default.
///
/// Per the approved Stage 5 decision: only [captureFromCamera] (rear lens
/// preferred, no in-app front-camera option) and [pickFromGallery] exist —
/// there is no front-camera affordance anywhere in this app's own UI. The
/// customer's device camera app may still expose its own flip control; that
/// is a platform-level limitation this app cannot suppress, and is disclosed
/// in the Stage 5 plan rather than silently overclaimed.
abstract class VirtualTryOnPhotoPickerService {
  /// Opens the platform camera, preferring the rear lens. Returns the
  /// captured photo's raw bytes, or `null` if the user cancelled.
  Future<Uint8List?> captureFromCamera();

  /// Opens the platform photo gallery/picker. Returns the picked photo's raw
  /// bytes, or `null` if the user cancelled.
  Future<Uint8List?> pickFromGallery();
}
