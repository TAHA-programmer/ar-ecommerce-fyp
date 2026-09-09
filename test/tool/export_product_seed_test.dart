import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_product_seed_data.dart';

import '../../tool/export_product_seed.dart';

void main() {
  group('export_product_seed — deterministic export', () {
    test('repeated export is byte-stable (addedDate preserved)', () {
      // Each buildMockProductSeedData() call re-stamps addedDate from
      // DateTime.now(); the export must still be identical run-to-run once a
      // prior products_seed.json exists.
      final first = buildSeedExport(buildMockProductSeedData());
      final second = buildSeedExport(
        buildMockProductSeedData(),
        previous: first,
      );
      final third = buildSeedExport(
        buildMockProductSeedData(),
        previous: second,
      );

      expect(jsonEncode(second), jsonEncode(first));
      expect(jsonEncode(third), jsonEncode(second));
    });

    test('re-export against a stale prior changes ONLY the recast fields', () {
      // Simulate the pre-R13/R14 products_seed.json for the four AR products
      // (old title / specs / no ar*), everything else already current.
      // Only these four carry the pre-R13/R14 stale shape in this simulated
      // prior; every other product (including the Phase 9.2 coverage-
      // expansion ids, which now also carry ar* fields) must be left exactly
      // as `current` produced it.
      const staleFour = {
        'luna-accent-chair',
        'glass-coffee-table',
        'luna-3-seater-sofa',
        'modern-table-lamp',
      };
      final current = buildSeedExport(buildMockProductSeedData());
      final stalePrior = current.map((p) {
        final m = Map<String, dynamic>.from(p);
        switch (m['id']) {
          case 'glass-coffee-table':
            m['title'] = 'Glass Coffee Table';
            m['specifications'] = const <Map<String, String>>[];
            break;
          case 'luna-3-seater-sofa':
            m['title'] = 'Luna 3-Seater Sofa';
            m['specifications'] = const [
              {'label': 'Material', 'value': 'Premium Fabric'},
              {'label': 'Dimensions', 'value': 'W 200 cm • D 85 cm • H 82 cm'},
            ];
            break;
          case 'modern-table-lamp':
            m['specifications'] = const [
              {'label': 'Material', 'value': 'Brass & Glass'},
              {'label': 'Dimensions', 'value': 'H 45 cm • W 20 cm'},
              {'label': 'Bulb Type', 'value': 'E27 LED'},
            ];
            break;
        }
        // strip the ar* keys from the stale prior, but only for the three
        // products actually simulating the pre-R13/R14 stale shape above —
        // NOT every product (a bare `.map()`-wide strip was harmless while
        // only these three carried ar* fields at all, but would now also
        // wrongly strip the Phase 9.2 coverage-expansion products' fields).
        if (staleFour.contains(m['id'])) {
          for (final k in const [
            'arModelStoragePath',
            'arModelFormat',
            'arModelVersion',
            'arModelSha256',
            'arWidthM',
            'arDepthM',
            'arHeightM',
            'arScaleContract',
          ]) {
            m.remove(k);
          }
        }
        return m;
      }).toList();

      final reExported = buildSeedExport(
        buildMockProductSeedData(),
        previous: stalePrior,
      );

      final byId = {for (final p in stalePrior) p['id'] as String: p};
      final changedFields = <String, Set<String>>{};
      for (final p in reExported) {
        final id = p['id'] as String;
        final old = byId[id]!;
        for (final key in {...p.keys, ...old.keys}) {
          if (jsonEncode(p[key]) != jsonEncode(old[key])) {
            (changedFields[id] ??= <String>{}).add(key);
          }
        }
      }

      // Only the four AR products change, and only their recast fields.
      expect(changedFields.keys.toSet(), {
        'glass-coffee-table',
        'modern-table-lamp',
        'luna-3-seater-sofa',
        'luna-accent-chair',
      });
      const allowed = {
        'title',
        'description',
        'specifications',
        'arModelStoragePath',
        'arModelFormat',
        'arModelVersion',
        'arModelSha256',
        'arWidthM',
        'arDepthM',
        'arHeightM',
        'arScale',
        'arScaleContract',
      };
      for (final entry in changedFields.entries) {
        expect(
          entry.value.difference(allowed),
          isEmpty,
          reason: '${entry.key} changed unexpected fields: ${entry.value}',
        );
        // addedDate specifically must be preserved
        expect(entry.value.contains('addedDate'), isFalse);
      }
    });

    test(
      'a genuinely new product (not in prior) keeps its fresh addedDate',
      () {
        final products = buildMockProductSeedData();
        // prior missing one id entirely
        final prior = buildSeedExport(
          products,
        ).where((p) => p['id'] != 'luna-accent-chair').toList();
        final out = buildSeedExport(products, previous: prior);
        final chair = out.firstWhere((p) => p['id'] == 'luna-accent-chair');
        expect(chair['addedDate'], isA<String>());
        expect((chair['addedDate'] as String).isNotEmpty, isTrue);
      },
    );
  });
}
