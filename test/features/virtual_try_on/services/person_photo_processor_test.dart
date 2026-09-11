import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:twin_ar/features/virtual_try_on/services/person_photo_processor.dart';

Uint8List _pngBytes({int width = 800, int height = 1200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(120, 150, 90));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _jpegBytes({int width = 800, int height = 1200}) {
  final image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(80, 90, 200));
  return Uint8List.fromList(img.encodeJpg(image));
}

void main() {
  group('PersonPhotoProcessor.processToJpeg', () {
    test('re-encodes a PNG source to real JPEG bytes', () {
      final result = PersonPhotoProcessor.processToJpeg(_pngBytes());
      final decoded = img.decodeJpg(result);
      expect(decoded, isNotNull);
      // JPEG magic bytes.
      expect(result[0], 0xFF);
      expect(result[1], 0xD8);
    });

    test('passes through an already-JPEG source as JPEG', () {
      final result = PersonPhotoProcessor.processToJpeg(_jpegBytes());
      expect(img.decodeJpg(result), isNotNull);
    });

    test('downscales an oversized image to the target long edge', () {
      final result = PersonPhotoProcessor.processToJpeg(
        _pngBytes(width: 3000, height: 4000),
      );
      final decoded = img.decodeJpg(result)!;
      expect(decoded.height, PersonPhotoProcessor.targetLongEdgePx);
      expect(decoded.width, lessThan(decoded.height));
    });

    test('leaves an already-small image at its own resolution', () {
      final result = PersonPhotoProcessor.processToJpeg(
        _pngBytes(width: 400, height: 600),
      );
      final decoded = img.decodeJpg(result)!;
      expect(decoded.width, 400);
      expect(decoded.height, 600);
    });

    test('rejects empty bytes', () {
      expect(
        () => PersonPhotoProcessor.processToJpeg(Uint8List(0)),
        throwsA(isA<PersonPhotoValidationException>()),
      );
    });

    test('rejects bytes that are not a decodable image', () {
      expect(
        () => PersonPhotoProcessor.processToJpeg(
          Uint8List.fromList(List.filled(100, 7)),
        ),
        throwsA(isA<PersonPhotoValidationException>()),
      );
    });

    test('rejects an implausibly small image', () {
      expect(
        () => PersonPhotoProcessor.processToJpeg(
          _pngBytes(width: 50, height: 50),
        ),
        throwsA(isA<PersonPhotoValidationException>()),
      );
    });

    test('rejects a source larger than maxSourceBytes', () {
      final oversized = Uint8List(PersonPhotoProcessor.maxSourceBytes + 1);
      expect(
        () => PersonPhotoProcessor.processToJpeg(oversized),
        throwsA(isA<PersonPhotoValidationException>()),
      );
    });

    test('never returns bytes above maxUploadBytes', () {
      final result = PersonPhotoProcessor.processToJpeg(
        _pngBytes(width: 2500, height: 3500),
      );
      expect(
        result.length,
        lessThanOrEqualTo(PersonPhotoProcessor.maxUploadBytes),
      );
    });
  });
}
