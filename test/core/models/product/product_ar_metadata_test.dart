import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';

void main() {
  const validSha =
      'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94';

  Map<String, dynamic> validMap({Map<String, dynamic> overrides = const {}}) =>
      {
        'arModelStoragePath': 'products/luna-accent-chair/ar/model-v1.glb',
        'arModelFormat': 'glb',
        'arModelVersion': '1',
        'arModelSha256': validSha,
        'arWidthM': 0.70,
        'arDepthM': 0.72,
        'arHeightM': 0.82,
        'arScale': 1.0,
        'arScaleContract': ProductArMetadata.currentScaleContract,
        ...overrides,
      };

  group('ProductArMetadata — complete valid contract', () {
    test('parses every field and is renderable', () {
      final ar = ProductArMetadata.fromProductData(validMap())!;
      expect(ar.storagePath, 'products/luna-accent-chair/ar/model-v1.glb');
      expect(ar.format, 'glb');
      expect(ar.modelVersion, '1');
      expect(ar.sha256, validSha);
      expect(ar.widthM, 0.70);
      expect(ar.depthM, 0.72);
      expect(ar.heightM, 0.82);
      expect(ar.scale, 1.0);
      expect(ar.scaleContract, ProductArMetadata.currentScaleContract);
      expect(ar.isRenderable, isTrue);
      expect(ProductArMetadata.validationIssues(validMap()), isEmpty);
      expect(ar.dimensionsM, (width: 0.70, depth: 0.72, height: 0.82));
    });

    test('round-trips through toFirestoreFields / fromProductData', () {
      final original = ProductArMetadata.fromProductData(validMap())!;
      final restored = ProductArMetadata.fromProductData(
        original.toFirestoreFields(),
      )!;
      expect(restored, original);
      expect(restored.isRenderable, isTrue);
    });

    test('int-typed Firestore numbers are accepted', () {
      final ar = ProductArMetadata.fromProductData(
        validMap(overrides: {'arWidthM': 1, 'arHeightM': 2, 'arScale': 1}),
      )!;
      expect(ar.widthM, 1.0);
      expect(ar.isRenderable, isTrue);
    });
  });

  group('ProductArMetadata — no metadata', () {
    test('an absent arModelStoragePath yields null (not an error)', () {
      expect(ProductArMetadata.fromProductData({'title': 'plain'}), isNull);
      expect(
        ProductArMetadata.fromProductData({'arModelStoragePath': '  '}),
        isNull,
      );
      expect(ProductArMetadata.validationIssues({'title': 'plain'}), [
        'no AR model metadata',
      ]);
      expect(ProductArMetadata.validationIssues(null), [
        'no AR model metadata',
      ]);
    });
  });

  group('ProductArMetadata — missing optional / incomplete', () {
    test('a present path with missing sibling fields parses but is NOT '
        'renderable, and reports honest issues', () {
      final data = {'arModelStoragePath': 'products/x/ar/model-v1.glb'};
      final ar = ProductArMetadata.fromProductData(data)!;
      expect(ar.isRenderable, isFalse);
      final issues = ProductArMetadata.validationIssues(data);
      expect(issues, contains('format must be "glb" (got "")'));
      expect(issues, contains('model version is missing'));
      expect(issues, contains('sha256 must be 64 lowercase hex characters'));
      expect(issues, contains('arWidthM must be > 0 and <= 100'));
      expect(issues, contains('scale-contract id is missing'));
    });

    test('a missing arScale defaults to 1.0 and stays renderable', () {
      final data = validMap()..remove('arScale');
      final ar = ProductArMetadata.fromProductData(data)!;
      expect(ar.scale, 1.0);
      expect(ar.isRenderable, isTrue);
    });
  });

  group('ProductArMetadata — malformed values fail safely', () {
    test('malformed dimensions', () {
      for (final bad in [0, -1, 'x', double.nan, 250]) {
        final ar = ProductArMetadata.fromProductData(
          validMap(overrides: {'arWidthM': bad}),
        )!;
        expect(ar.isRenderable, isFalse, reason: 'arWidthM=$bad');
        expect(
          ProductArMetadata.validationIssues(
            validMap(overrides: {'arDepthM': bad}),
          ),
          contains('arDepthM must be > 0 and <= 100'),
        );
      }
    });

    test('malformed sha256 (wrong length / uppercase / not hex)', () {
      for (final bad in ['abc', validSha.toUpperCase(), 'z' * 64, 12345]) {
        expect(
          ProductArMetadata.fromProductData(
            validMap(overrides: {'arModelSha256': bad}),
          )!.isRenderable,
          isFalse,
          reason: 'sha=$bad',
        );
      }
    });

    test('malformed version (empty)', () {
      expect(
        ProductArMetadata.fromProductData(
          validMap(overrides: {'arModelVersion': '   '}),
        )!.isRenderable,
        isFalse,
      );
    });

    test('malformed format (not glb)', () {
      expect(
        ProductArMetadata.validationIssues(
          validMap(overrides: {'arModelFormat': 'usdz'}),
        ),
        contains('format must be "glb" (got "usdz")'),
      );
    });

    test('malformed storage path — URL / Windows path / asset path / signed '
        'URL / wrong extension all rejected', () {
      final bad = {
        'https://cdn.example.com/model.glb': 'URL',
        r'C:\models\chair.glb': 'Windows',
        'assets/models/chair.glb': 'asset',
        'products/x/ar/model.glb?token=abc': 'signed',
        '/products/x/ar/model.glb': 'absolute',
        'products/x/ar/model.gltf': 'wrong ext',
      };
      for (final entry in bad.entries) {
        final ar = ProductArMetadata.fromProductData(
          validMap(overrides: {'arModelStoragePath': entry.key}),
        )!;
        expect(ar.isRenderable, isFalse, reason: entry.value);
      }
    });

    test('malformed scale (0 / negative / huge)', () {
      for (final bad in [0, -0.5, 25.0]) {
        expect(
          ProductArMetadata.fromProductData(
            validMap(overrides: {'arScale': bad}),
          )!.isRenderable,
          isFalse,
          reason: 'scale=$bad',
        );
      }
    });
  });

  group('ProductArMetadata — value semantics', () {
    test('== / hashCode', () {
      final a = ProductArMetadata.fromProductData(validMap())!;
      final b = ProductArMetadata.fromProductData(validMap())!;
      expect(a, b);
      expect(a.hashCode, b.hashCode);
      expect(a == a.copyWith(modelVersion: '2'), isFalse);
    });

    test('copyWith', () {
      final a = ProductArMetadata.fromProductData(validMap())!;
      final c = a.copyWith(modelVersion: '3', scale: 1.1);
      expect(c.modelVersion, '3');
      expect(c.scale, 1.1);
      expect(c.storagePath, a.storagePath);
    });
  });

  group('ProductArMetadata.belongsToProduct — cross-product path defence', () {
    test('accepts the exact expected path for the given product id', () {
      final ar = ProductArMetadata.fromProductData(validMap())!;
      expect(ar.belongsToProduct('luna-accent-chair'), isTrue);
    });

    test('rejects a different product id even if the path is well-formed', () {
      final ar = ProductArMetadata.fromProductData(validMap())!;
      expect(ar.belongsToProduct('velvet-armchair'), isFalse);
      expect(ar.belongsToProduct('glass-coffee-table'), isFalse);
    });

    test('rejects when only the model version segment differs', () {
      final ar = ProductArMetadata.fromProductData(
        validMap(
          overrides: {
            'arModelStoragePath': 'products/luna-accent-chair/ar/model-v2.glb',
          },
        ),
      )!;
      // modelVersion is still "1" (unchanged override), so the expected path
      // for v1 no longer matches the actual (v2) path on the object.
      expect(ar.belongsToProduct('luna-accent-chair'), isFalse);
    });
  });
}
