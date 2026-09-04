import 'image_picker_service.dart';

/// In-memory test double for [ImagePickerService]. Not used in production.
class MockImagePickerService implements ImagePickerService {
  String? gallerySingleResult;
  String? cameraSingleResult;
  List<String> multiImageResult = const [];

  @override
  Future<String?> pickImageFromGallery() async => gallerySingleResult;

  @override
  Future<String?> pickImageFromCamera() async => cameraSingleResult;

  @override
  Future<List<String>> pickMultipleImagesFromGallery({int? maxImages}) async {
    if (maxImages == null) return multiImageResult;
    return multiImageResult.take(maxImages).toList();
  }
}
