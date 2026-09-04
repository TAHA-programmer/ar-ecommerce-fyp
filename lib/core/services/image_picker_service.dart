/// Abstraction over device image selection (gallery/camera), so ViewModels
/// and Views depend on an injectable interface rather than instantiating
/// `package:image_picker`'s `ImagePicker` directly - consistent with this
/// project's Repository/Service pattern and needed to unit-test upload
/// flows (`AdminProductFormViewModel`, avatar upload) without a real device
/// picker channel. `DeviceImagePickerService` is the real implementation;
/// `MockImagePickerService` (test-only) returns configured, deterministic
/// results.
///
/// Every method returns `null`/an empty list on cancellation or a denied
/// permission - `image_picker` itself does not distinguish the two at the
/// Dart API level, so callers treat both as "no selection was made", never
/// as an error to surface via `AppToast`.
abstract class ImagePickerService {
  /// Picks a single image from the device gallery. Returns the local file
  /// path, or `null` if the user cancelled or permission was denied.
  Future<String?> pickImageFromGallery();

  /// Captures a single photo via the device camera. Returns the local file
  /// path, or `null` if the user cancelled or permission was denied.
  Future<String?> pickImageFromCamera();

  /// Picks multiple images from the device gallery, capped at [maxImages].
  /// Returns an empty list if the user cancelled or permission was denied -
  /// never throws for that case.
  Future<List<String>> pickMultipleImagesFromGallery({int? maxImages});
}
