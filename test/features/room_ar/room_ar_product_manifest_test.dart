import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_product_seed_data.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/features/room_ar/room_ar_product_manifest.dart';

void main() {
  group('RoomArProductManifest — the four approved products', () {
    test('keyed by the current Firestore product ids', () {
      expect(RoomArProductManifest.byProductId.keys.toSet(), {
        'luna-accent-chair',
        'glass-coffee-table',
        'modern-table-lamp',
        'luna-3-seater-sofa',
      });
    });

    test('every entry is a fully valid, renderable contract', () {
      for (final entry in RoomArProductManifest.byProductId.entries) {
        expect(entry.value.isRenderable, isTrue, reason: entry.key);
        expect(
          ProductArMetadata.validationIssues(entry.value.toFirestoreFields()),
          isEmpty,
          reason: entry.key,
        );
      }
    });

    test('exact verified SHA-256 per product', () {
      expect(
        RoomArProductManifest.byProductId['luna-accent-chair']!.sha256,
        'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
      );
      expect(
        RoomArProductManifest.byProductId['glass-coffee-table']!.sha256,
        'd10f32a7373d84031d3e51b8e9770610f514f62fa56110608852f1640ab7a727',
      );
      expect(
        RoomArProductManifest.byProductId['modern-table-lamp']!.sha256,
        'ee417ead58e72de9518358288f089bad272779c190125e01ac372fcfc16bb565',
      );
      expect(
        RoomArProductManifest.byProductId['luna-3-seater-sofa']!.sha256,
        'efd400046b265fd49d8d2b0382d378d230d625cb879740a3ef0697ca86c0d187',
      );
    });

    test('exact verified W×D×H metres per product', () {
      ({double width, double depth, double height}) dims(String id) =>
          RoomArProductManifest.byProductId[id]!.dimensionsM;
      expect(dims('luna-accent-chair'), (
        width: 0.70,
        depth: 0.72,
        height: 0.82,
      ));
      expect(dims('glass-coffee-table'), (
        width: 0.90,
        depth: 0.90,
        height: 0.42,
      ));
      expect(dims('modern-table-lamp'), (
        width: 0.20,
        depth: 0.20,
        height: 0.45,
      ));
      expect(dims('luna-3-seater-sofa'), (
        width: 2.65,
        depth: 1.65,
        height: 0.82,
      ));
    });

    test('glb format, version 1, scale 1.0, current scale-contract', () {
      for (final ar in RoomArProductManifest.byProductId.values) {
        expect(ar.format, 'glb');
        expect(ar.modelVersion, '1');
        expect(ar.scale, 1.0);
        expect(ar.scaleContract, ProductArMetadata.currentScaleContract);
      }
    });

    test('storage paths are Storage object paths under products/{id}/ar/', () {
      for (final entry in RoomArProductManifest.byProductId.entries) {
        final p = entry.value.storagePath;
        expect(p, startsWith('products/${entry.key}/ar/'));
        expect(p, endsWith('.glb'));
        expect(p, isNot(contains('://')));
        expect(p, isNot(contains(r'\')));
        expect(p, isNot(contains('?')));
      }
      expect(
        RoomArProductManifest.storagePathFor('foo', version: '3'),
        'products/foo/ar/model-v3.glb',
      );
    });

    test(
      'kRoomArProductMetadata in the canonical seed is byte-identical to the '
      'manifest (R13/R14 — one source of truth)',
      () {
        expect(
          kRoomArProductMetadata.keys.toSet(),
          RoomArProductManifest.byProductId.keys.toSet(),
        );
        for (final id in RoomArProductManifest.byProductId.keys) {
          expect(
            kRoomArProductMetadata[id],
            RoomArProductManifest.byProductId[id],
            reason: id,
          );
        }
      },
    );
  });
}
