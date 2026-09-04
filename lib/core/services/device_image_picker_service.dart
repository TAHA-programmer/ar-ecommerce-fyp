import 'package:image_picker/image_picker.dart';
import 'image_picker_service.dart';

/// Real device implementation of [ImagePickerService], wrapping
/// `package:image_picker`. Replaces the narrower, non-injectable
/// `ProfileImagePicker` as the single picker used by both the Admin product
/// image flow and the Customer avatar flow.
///
/// Both pick paths downscale/compress at pick time via `image_picker`'s own
/// `maxWidth`/`maxHeight`/`imageQuality` - a real phone camera photo
/// (commonly 10-20+ MB) would otherwise fail `storage.rules`' size limits
/// outright, or at minimum waste bandwidth/storage for no visual benefit at
/// the sizes this app ever actually displays an image at. Avatars are
/// capped smaller than product photos since they only ever render as a
/// small circle; product photos keep enough resolution for a full-screen
/// zoom on Product Details. This is a best-effort size reduction, not a
/// substitute for the hard preflight validation in
/// `image_upload_validator.dart`, which still runs on whatever file this
/// produces immediately before any Storage write.
class DeviceImagePickerService implements ImagePickerService {
  static const double _avatarMaxDimension = 1024;
  static const int _avatarQuality = 85;
  static const double _productImageMaxDimension = 1600;
  static const int _productImageQuality = 85;

  final ImagePicker _picker;

  DeviceImagePickerService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  @override
  Future<String?> pickImageFromGallery() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: _avatarMaxDimension,
        maxHeight: _avatarMaxDimension,
        imageQuality: _avatarQuality,
      );
      return image?.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<String?> pickImageFromCamera() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: _avatarMaxDimension,
        maxHeight: _avatarMaxDimension,
        imageQuality: _avatarQuality,
      );
      return image?.path;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<String>> pickMultipleImagesFromGallery({int? maxImages}) async {
    try {
      final images = await _picker.pickMultiImage(
        limit: maxImages,
        maxWidth: _productImageMaxDimension,
        maxHeight: _productImageMaxDimension,
        imageQuality: _productImageQuality,
      );
      return images.map((x) => x.path).toList();
    } catch (_) {
      return const [];
    }
  }
}
