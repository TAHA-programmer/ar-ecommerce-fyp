import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/utils/image_upload_validator.dart';
import '../../support/test_image_files.dart';

void main() {
  tearDown(() async {
    await TestImageFile.cleanUp();
  });

  group('validateImageFileForUpload', () {
    test('accepts a real, supported-type file under the size limit', () async {
      final file = await TestImageFile.create(
        extension: 'jpg',
        sizeBytes: 1024,
      );

      await expectLater(
        validateImageFileForUpload(file, maxSizeBytes: avatarMaxUploadBytes),
        completes,
      );
    });

    test('accepts png and webp, not just jpg/jpeg', () async {
      final png = await TestImageFile.create(extension: 'png');
      final webp = await TestImageFile.create(extension: 'webp');
      final jpeg = await TestImageFile.create(extension: 'jpeg');

      await expectLater(
        validateImageFileForUpload(png, maxSizeBytes: avatarMaxUploadBytes),
        completes,
      );
      await expectLater(
        validateImageFileForUpload(webp, maxSizeBytes: avatarMaxUploadBytes),
        completes,
      );
      await expectLater(
        validateImageFileForUpload(jpeg, maxSizeBytes: avatarMaxUploadBytes),
        completes,
      );
    });

    test('rejects a file that does not exist on disk', () async {
      final missing = File(
        '${Directory.systemTemp.path}/does-not-exist-twin-ar-validator-test.jpg',
      );

      await expectLater(
        validateImageFileForUpload(missing, maxSizeBytes: avatarMaxUploadBytes),
        throwsA(isA<ImageValidationException>()),
      );
    });

    test('rejects an unsupported extension (e.g. gif)', () async {
      final file = await TestImageFile.create(extension: 'gif');

      await expectLater(
        validateImageFileForUpload(file, maxSizeBytes: avatarMaxUploadBytes),
        throwsA(
          isA<ImageValidationException>().having(
            (e) => e.message,
            'message',
            contains('Unsupported'),
          ),
        ),
      );
    });

    test('rejects a file with no extension at all', () async {
      final file = await TestImageFile.create(extension: '');

      await expectLater(
        validateImageFileForUpload(file, maxSizeBytes: avatarMaxUploadBytes),
        throwsA(isA<ImageValidationException>()),
      );
    });

    test('rejects a file over the avatar size limit (2MB)', () async {
      final file = await TestImageFile.create(
        sizeBytes: avatarMaxUploadBytes + 1,
      );

      await expectLater(
        validateImageFileForUpload(
          file,
          maxSizeBytes: avatarMaxUploadBytes,
          label: 'photo',
        ),
        throwsA(
          isA<ImageValidationException>().having(
            (e) => e.message,
            'message',
            contains('too large'),
          ),
        ),
      );
    });

    test('accepts a file exactly at the size limit (boundary)', () async {
      final file = await TestImageFile.create(sizeBytes: avatarMaxUploadBytes);

      await expectLater(
        validateImageFileForUpload(file, maxSizeBytes: avatarMaxUploadBytes),
        completes,
      );
    });

    test('rejects a file over the product-image size limit (10MB)', () async {
      final file = await TestImageFile.create(
        sizeBytes: productImageMaxUploadBytes + 1,
      );

      await expectLater(
        validateImageFileForUpload(
          file,
          maxSizeBytes: productImageMaxUploadBytes,
        ),
        throwsA(isA<ImageValidationException>()),
      );
    });

    test(
      'never throws a raw exception type - always ImageValidationException',
      () async {
        final missing = File('${Directory.systemTemp.path}/nope.jpg');
        try {
          await validateImageFileForUpload(
            missing,
            maxSizeBytes: avatarMaxUploadBytes,
          );
          fail('expected an exception');
        } catch (e) {
          expect(e, isA<ImageValidationException>());
          expect(e, isNot(isA<FileSystemException>()));
        }
      },
    );
  });
}
