import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_product_seed_data.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/features/room_ar/room_ar_product_manifest.dart';

const _beigeArRugIds = [
  'beige-ar-in-stock-5',
  'beige-ar-in-stock-7',
  'beige-ar-in-stock-11',
  'beige-ar-in-stock-13',
  'beige-ar-in-stock-17',
  'beige-ar-in-stock-19',
  'beige-ar-in-stock-23',
];

const _beigeArSofaIds = [
  'beige-ar-in-stock-2',
  'beige-ar-in-stock-4',
  'beige-ar-in-stock-8',
  'beige-ar-in-stock-10',
  'beige-ar-in-stock-14',
  'beige-ar-in-stock-16',
  'beige-ar-in-stock-20',
  'beige-ar-in-stock-22',
];

const _beigeArVaseIds = [
  'beige-ar-in-stock-3',
  'beige-ar-in-stock-6',
  'beige-ar-in-stock-9',
  'beige-ar-in-stock-12',
  'beige-ar-in-stock-15',
  'beige-ar-in-stock-18',
  'beige-ar-in-stock-21',
  'beige-ar-in-stock-24',
];

void main() {
  group('RoomArProductManifest — the four approved products', () {
    test('keyed by the current Firestore product ids', () {
      expect(RoomArProductManifest.byProductId.keys.toSet(), {
        'luna-accent-chair',
        'glass-coffee-table',
        'modern-table-lamp',
        'luna-3-seater-sofa',
        'velvet-armchair',
        'wooden-console',
        'marble-side-table',
        ..._beigeArRugIds,
        ..._beigeArSofaIds,
        ..._beigeArVaseIds,
      });
      // 4 original + 3 individually-modelled + 7 + 8 + 8 shared-design ids.
      expect(RoomArProductManifest.byProductId.length, 30);
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

  group(
    'RoomArProductManifest — Phase 9.2 coverage-expansion (tracker §15)',
    () {
      test('exact verified SHA-256 + dims for the three individually-modelled '
          'products', () {
        final armchair = RoomArProductManifest.byProductId['velvet-armchair']!;
        expect(
          armchair.sha256,
          '9909929fdc84adf526127887ab782805bee0ff6863c04e0dd1510a4264f8a09e',
        );
        expect(armchair.dimensionsM, (width: 0.72, depth: 0.76, height: 0.78));

        final console = RoomArProductManifest.byProductId['wooden-console']!;
        expect(
          console.sha256,
          'b22ac85b25cac2b4924e04793701c95907c36474bb04df7c4aa9ddda51e03433',
        );
        expect(console.dimensionsM, (width: 1.80, depth: 0.42, height: 0.72));

        final sideTable =
            RoomArProductManifest.byProductId['marble-side-table']!;
        expect(
          sideTable.sha256,
          '287b8bb97b3bff21de651b49dbb46024be0462fc2ea3e49c6a08964f79b9b7b3',
        );
        expect(sideTable.dimensionsM, (width: 0.46, depth: 0.46, height: 0.53));
      });

      test('each beige-ar-in-stock shared-design group has identical SHA-256 + '
          'dims across every member, but a distinct per-id storage path', () {
        void checkGroup(
          List<String> ids,
          String expectedSha256,
          ({double width, double depth, double height}) expectedDims,
        ) {
          final paths = <String>{};
          for (final id in ids) {
            final ar = RoomArProductManifest.byProductId[id];
            expect(ar, isNotNull, reason: id);
            expect(ar!.sha256, expectedSha256, reason: id);
            expect(ar.dimensionsM, expectedDims, reason: id);
            expect(ar.storagePath, 'products/$id/ar/model-v1.glb');
            paths.add(ar.storagePath);
          }
          // Every id in the group has its own Storage object path — a
          // shared design never collapses into a shared path (rule 9).
          expect(paths.length, ids.length);
        }

        checkGroup(
          _beigeArRugIds,
          'd21f1adaf04708ff96976282fa7543814c9718028a3297fe392b0847766837e5',
          (width: 2.00, depth: 1.35, height: 0.012),
        );
        checkGroup(
          _beigeArSofaIds,
          '5dfc2a86ea7a9c66ca4190179a31e1d2f2b28c9829cbd9b2240b9284c7db2a84',
          (width: 2.50, depth: 1.60, height: 0.70),
        );
        checkGroup(
          _beigeArVaseIds,
          'cf8c32bab30e43ca138fd07b5aca50a792389d91228aaacb05cb09321989295d',
          (width: 0.15, depth: 0.15, height: 0.20),
        );

        // The six distinct GLB designs must not collide with each other.
        final allSha256 = {
          RoomArProductManifest.byProductId['velvet-armchair']!.sha256,
          RoomArProductManifest.byProductId['wooden-console']!.sha256,
          RoomArProductManifest.byProductId['marble-side-table']!.sha256,
          RoomArProductManifest.byProductId[_beigeArRugIds.first]!.sha256,
          RoomArProductManifest.byProductId[_beigeArSofaIds.first]!.sha256,
          RoomArProductManifest.byProductId[_beigeArVaseIds.first]!.sha256,
        };
        expect(allSha256.length, 6);
      });
    },
  );
}
