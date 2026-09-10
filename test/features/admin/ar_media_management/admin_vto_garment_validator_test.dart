import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/admin/ar_media_management/utils/admin_vto_garment_validator.dart';

import 'vto_garment_test_support.dart';

void main() {
  late Directory tmp;

  setUp(() => tmp = Directory.systemTemp.createTempSync('vto_validator_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  group('inspectVtoGarmentFile — accepts', () {
    test(
      'a valid PNG returns size, sha256, contentType and dimensions',
      () async {
        final file = writePng(tmp, 'garment.png', width: 900, height: 1200);
        final result = await inspectVtoGarmentFile(file);
        expect(result.contentType, 'image/png');
        expect(result.width, 900);
        expect(result.height, 1200);
        expect(result.sizeBytes, file.lengthSync());
        expect(result.sha256, matches(RegExp(r'^[0-9a-f]{64}$')));
        expect(result.isBelowRecommendedResolution, isFalse);
      },
    );

    test('a valid JPEG header returns image/jpeg + dimensions', () async {
      final file = writeJpegHeader(
        tmp,
        'garment.jpg',
        width: 1024,
        height: 768,
      );
      final result = await inspectVtoGarmentFile(file);
      expect(result.contentType, 'image/jpeg');
      expect(result.width, 1024);
      expect(result.height, 768);
      expect(result.fileExtension, 'jpg');
    });

    test(
      'a low-res but usable image flags isBelowRecommendedResolution',
      () async {
        final file = writePng(tmp, 'small.png', width: 400, height: 500);
        final result = await inspectVtoGarmentFile(file);
        expect(result.isBelowRecommendedResolution, isTrue);
      },
    );
  });

  group('inspectVtoGarmentFile — rejects', () {
    test('a missing file', () async {
      await expectLater(
        inspectVtoGarmentFile(File('${tmp.path}/nope.png')),
        throwsA(isA<GarmentValidationException>()),
      );
    });

    test('an unsupported extension', () async {
      final file = File('${tmp.path}/garment.webp')
        ..writeAsBytesSync(buildPngBytes(width: 800, height: 800));
      await expectLater(
        inspectVtoGarmentFile(file),
        throwsA(
          isA<GarmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('JPEG or PNG'),
          ),
        ),
      );
    });

    test('an empty file', () async {
      final file = File('${tmp.path}/empty.png')..writeAsBytesSync([]);
      await expectLater(
        inspectVtoGarmentFile(file),
        throwsA(isA<GarmentValidationException>()),
      );
    });

    test('a file over the 8 MiB authoring budget', () async {
      final big = writePng(
        tmp,
        'big.png',
        width: 3000,
        height: 800,
        fill: 0x10,
      );
      // ~3000*800 stored bytes ≈ 2.4 MB; force well over 8 MiB.
      final bytes = big.readAsBytesSync();
      final padded = File('${tmp.path}/padded.png')
        ..writeAsBytesSync([...bytes, ...List.filled(9 * 1024 * 1024, 0)]);
      await expectLater(
        inspectVtoGarmentFile(padded),
        throwsA(
          isA<GarmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('8 MB'),
          ),
        ),
      );
    });

    test('a PNG masquerading as .jpg (signature/extension mismatch)', () async {
      final file = File('${tmp.path}/liar.jpg')
        ..writeAsBytesSync(buildPngBytes(width: 800, height: 800));
      await expectLater(
        inspectVtoGarmentFile(file),
        throwsA(
          isA<GarmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('really a PNG'),
          ),
        ),
      );
    });

    test('junk bytes with an image extension (no valid signature)', () async {
      final file = writeFakeImage(tmp, 'junk.png');
      await expectLater(
        inspectVtoGarmentFile(file),
        throwsA(
          isA<GarmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('not a valid JPEG or PNG'),
          ),
        ),
      );
    });

    test('an image below the 256 px hard minimum', () async {
      final file = writePng(tmp, 'tiny.png', width: 120, height: 200);
      await expectLater(
        inspectVtoGarmentFile(file),
        throwsA(
          isA<GarmentValidationException>().having(
            (e) => e.message,
            'message',
            contains('too small'),
          ),
        ),
      );
    });
  });

  test('sniff + dimension helpers round-trip the bytes', () {
    final png = buildPngBytes(width: 640, height: 480);
    expect(sniffVtoImageContentType(png), 'image/png');
    expect(readVtoImageDimensions(png, 'image/png'), (640, 480));

    final jpg = buildJpegHeaderBytes(width: 500, height: 700);
    expect(sniffVtoImageContentType(jpg), 'image/jpeg');
    expect(readVtoImageDimensions(jpg, 'image/jpeg'), (500, 700));
  });
}
