import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/admin/ar_media_management/models/admin_vto_garment_candidate.dart';

void main() {
  AdminVtoGarmentCandidate make({
    String slot = 'black',
    String contentType = 'image/jpeg',
    int version = 1,
    int width = 900,
    int height = 1200,
  }) => AdminVtoGarmentCandidate(
    file: File('/tmp/pick.jpg'),
    slot: slot,
    sizeBytes: 12345,
    sha256: 'a' * 64,
    contentType: contentType,
    width: width,
    height: height,
    targetVersion: version,
  );

  test(
    'storagePathFor + toAsset agree with VtoGarmentAsset.matchesExpectedPath',
    () {
      final c = make(slot: 'blue', contentType: 'image/png', version: 3);
      final path = c.storagePathFor('mens-oxford-shirt');
      expect(path, 'products/mens-oxford-shirt/vto/garment-blue-v3.png');
      final asset = c.toAsset(storagePath: path);
      expect(asset.matchesExpectedPath('mens-oxford-shirt', 'blue'), isTrue);
      expect(asset.isRenderable, isTrue);
      expect(asset.version, 3);
      expect(asset.byteSize, 12345);
    },
  );

  test('default slot resolves to the literal "default"', () {
    final c = make(slot: 'default', contentType: 'image/jpeg', version: 1);
    expect(c.isDefaultSlot, isTrue);
    expect(c.storagePathFor('p'), 'products/p/vto/garment-default-v1.jpg');
    expect(
      c
          .toAsset(storagePath: c.storagePathFor('p'))
          .matchesExpectedPath('p', 'default'),
      isTrue,
    );
  });

  test('fileExtension follows the content type, never .jpeg', () {
    expect(make(contentType: 'image/png').fileExtension, 'png');
    expect(make(contentType: 'image/jpeg').fileExtension, 'jpg');
  });

  test('provenance carries the sha256 + numeric version + dimensions', () {
    final p = make(version: 2, width: 640, height: 800).provenance();
    expect(p['twinArVtoSha256'], 'a' * 64);
    expect(p['twinArVtoVersion'], '2');
    expect(p['twinArVtoWidth'], '640');
    expect(p['twinArVtoHeight'], '800');
    expect(p['twinArVtoContentType'], 'image/jpeg');
  });

  test('isBelowRecommendedResolution follows the longest edge', () {
    expect(make(width: 300, height: 900).isBelowRecommendedResolution, isFalse);
    expect(make(width: 300, height: 500).isBelowRecommendedResolution, isTrue);
  });
}
