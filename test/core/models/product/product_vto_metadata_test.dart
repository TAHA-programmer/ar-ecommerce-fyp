import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_vto_metadata.dart';

void main() {
  // exactly 64 lowercase hex chars
  final sha = '0123456789abcdef' * 4;
  final sha2 = 'abcdef0123456789' * 4;

  Map<String, dynamic> assetMap({Map<String, dynamic> overrides = const {}}) =>
      {
        'storagePath': 'products/mens-oxford-shirt/vto/garment-blue-v1.jpg',
        'sha256': sha,
        'contentType': 'image/jpeg',
        'byteSize': 850000,
        'width': 1286,
        'height': 1223,
        'version': 1,
        ...overrides,
      };

  Map<String, dynamic> vtoMap({Map<String, dynamic> overrides = const {}}) => {
    'vtoGarmentCategory': 'top',
    'vtoContract': ProductVtoMetadata.currentContract,
    'vtoGarments': {'blue': assetMap()},
    ...overrides,
  };

  group('VtoGarmentAsset — valid', () {
    test('parses every field and is renderable', () {
      final a = VtoGarmentAsset.fromMap(assetMap())!;
      expect(
        a.storagePath,
        'products/mens-oxford-shirt/vto/garment-blue-v1.jpg',
      );
      expect(a.sha256, sha);
      expect(a.contentType, 'image/jpeg');
      expect(a.byteSize, 850000);
      expect(a.width, 1286);
      expect(a.height, 1223);
      expect(a.version, 1);
      expect(a.isRenderable, isTrue);
      expect(a.issues, isEmpty);
      expect(a.fileExtension, 'jpg');
      expect(a.isBelowRecommendedResolution, isFalse);
    });

    test('round-trips through toMap / fromMap', () {
      final a = VtoGarmentAsset.fromMap(assetMap())!;
      final b = VtoGarmentAsset.fromMap(a.toMap())!;
      expect(b, a);
      expect(b.hashCode, a.hashCode);
      expect(b.isRenderable, isTrue);
    });

    test(
      'int-typed Firestore numbers accepted; png path + type consistent',
      () {
        final a = VtoGarmentAsset.fromMap(
          assetMap(
            overrides: {
              'storagePath': 'products/x/vto/garment-default-v2.png',
              'contentType': 'image/png',
              'byteSize': 1,
              'version': 2,
            },
          ),
        )!;
        expect(a.contentType, 'image/png');
        expect(a.fileExtension, 'png');
        expect(a.isRenderable, isTrue);
      },
    );

    test('matchesExpectedPath enforces product id + slot + version + ext', () {
      final a = VtoGarmentAsset.fromMap(assetMap())!;
      expect(a.matchesExpectedPath('mens-oxford-shirt', 'blue'), isTrue);
      expect(a.matchesExpectedPath('other-product', 'blue'), isFalse);
      expect(a.matchesExpectedPath('mens-oxford-shirt', 'green'), isFalse);
      final v2 = a.copyWith(version: 2);
      expect(v2.matchesExpectedPath('mens-oxford-shirt', 'blue'), isFalse);
    });

    test('below recommended resolution is flagged but still renderable', () {
      final a = VtoGarmentAsset.fromMap(
        assetMap(overrides: {'width': 300, 'height': 369}),
      )!;
      expect(a.isRenderable, isTrue);
      expect(a.isBelowRecommendedResolution, isTrue);
    });
  });

  group('VtoGarmentAsset — absent / malformed', () {
    test('non-map or missing storagePath yields null (not an error)', () {
      expect(VtoGarmentAsset.fromMap(null), isNull);
      expect(VtoGarmentAsset.fromMap('nope'), isNull);
      expect(VtoGarmentAsset.fromMap(const <String, dynamic>{}), isNull);
      expect(VtoGarmentAsset.fromMap({'sha256': sha}), isNull);
      expect(VtoGarmentAsset.fromMap({'storagePath': '   '}), isNull);
    });

    test('present path + missing siblings parses but is NOT renderable', () {
      final a = VtoGarmentAsset.fromMap({
        'storagePath': 'products/x/vto/garment-blue-v1.jpg',
      })!;
      expect(a.isRenderable, isFalse);
      expect(a.issues, contains('sha256 must be 64 lowercase hex characters'));
      expect(
        a.issues,
        contains('contentType must be image/jpeg or image/png (got "")'),
      );
      expect(a.issues, contains('byteSize must be a whole number > 0'));
      expect(a.issues, contains('width must be a whole number in 1..20000'));
      expect(a.issues, contains('version must be a whole number >= 1'));
    });

    test('malformed sha256 (short / uppercase / not hex / not string)', () {
      for (final bad in ['abc', sha.toUpperCase(), 'z' * 64, 12345]) {
        expect(
          VtoGarmentAsset.fromMap(
            assetMap(overrides: {'sha256': bad}),
          )!.isRenderable,
          isFalse,
          reason: 'sha=$bad',
        );
      }
    });

    test('unsupported content type', () {
      final a = VtoGarmentAsset.fromMap(
        assetMap(overrides: {'contentType': 'image/webp'}),
      )!;
      expect(a.isRenderable, isFalse);
      expect(
        a.issues,
        contains(
          'contentType must be image/jpeg or image/png (got "image/webp")',
        ),
      );
    });

    test('content type / extension mismatch', () {
      final a = VtoGarmentAsset.fromMap(
        assetMap(
          overrides: {
            'storagePath': 'products/x/vto/garment-blue-v1.png',
            'contentType': 'image/jpeg',
          },
        ),
      )!;
      expect(a.isRenderable, isFalse);
      expect(
        a.issues,
        contains('contentType image/jpeg but path is not .jpg/.jpeg'),
      );
    });

    test('oversized byteSize rejected; huge dimensions rejected', () {
      expect(
        VtoGarmentAsset.fromMap(
          assetMap(overrides: {'byteSize': VtoGarmentAsset.maxBytes + 1}),
        )!.isRenderable,
        isFalse,
      );
      expect(
        VtoGarmentAsset.fromMap(
          assetMap(overrides: {'width': 99999}),
        )!.isRenderable,
        isFalse,
      );
    });

    test('bad storage path — URL / Windows / asset / signed / no /vto/ / wrong '
        'ext all rejected', () {
      final bad = <String, String>{
        'https://cdn.example.com/g.jpg': 'URL',
        r'C:\g\shirt.jpg': 'Windows',
        'assets/g/shirt.jpg': 'asset',
        '/products/x/vto/garment-blue-v1.jpg': 'absolute',
        'products/x/vto/garment-blue-v1.jpg?token=abc': 'signed',
        'products/x/images/garment-blue-v1.jpg': 'not under /vto/',
        'products/x/vto/garment-blue-v1.gif': 'wrong ext',
      };
      for (final e in bad.entries) {
        expect(
          VtoGarmentAsset.fromMap(
            assetMap(overrides: {'storagePath': e.key}),
          )!.isRenderable,
          isFalse,
          reason: e.value,
        );
      }
    });
  });

  group('ProductVtoMetadata — valid', () {
    test('parses category + per-colour garment and is renderable', () {
      final vto = ProductVtoMetadata.fromProductData(vtoMap())!;
      expect(vto.garmentCategory, 'top');
      expect(vto.contract, ProductVtoMetadata.currentContract);
      expect(vto.garmentsByColor.keys, ['blue']);
      expect(vto.garmentDefault, isNull);
      expect(vto.isRenderable, isTrue);
      expect(vto.issues, isEmpty);
      expect(ProductVtoMetadata.validationIssues(vtoMap()), isEmpty);
    });

    test('round-trips through toFirestoreFields / fromProductData', () {
      final original = ProductVtoMetadata.fromProductData(
        vtoMap(
          overrides: {
            'vtoGarments': {
              'blue': assetMap(),
              'green': assetMap(
                overrides: {
                  'storagePath':
                      'products/mens-oxford-shirt/vto/garment-green-v1.jpg',
                  'sha256': sha2,
                },
              ),
            },
            'vtoGarmentDefault': assetMap(
              overrides: {
                'storagePath':
                    'products/mens-oxford-shirt/vto/garment-default-v1.jpg',
              },
            ),
          },
        ),
      )!;
      final restored = ProductVtoMetadata.fromProductData({
        ...original.toFirestoreFields(),
      })!;
      expect(restored, original);
      expect(restored.hashCode, original.hashCode);
      expect(restored.isRenderable, isTrue);
      expect(restored.garmentsByColor.length, 2);
      expect(restored.garmentDefault, isNotNull);
    });

    test(
      'resolveGarment: per-colour wins, falls back to default, else null',
      () {
        final vto = ProductVtoMetadata.fromProductData(
          vtoMap(
            overrides: {
              'vtoGarments': {'blue': assetMap()},
              'vtoGarmentDefault': assetMap(
                overrides: {
                  'storagePath':
                      'products/mens-oxford-shirt/vto/garment-default-v1.jpg',
                },
              ),
            },
          ),
        )!;
        expect(
          vto.resolveGarment('blue')!.storagePath,
          contains('garment-blue'),
        );
        expect(
          vto.resolveGarment('green')!.storagePath,
          contains('garment-default'),
        );
        expect(
          vto.resolveGarment(null)!.storagePath,
          contains('garment-default'),
        );

        final noDefault = ProductVtoMetadata.fromProductData(vtoMap())!;
        expect(noDefault.resolveGarment('green'), isNull);
      },
    );

    test('assetsBelongToProduct enforces per-slot expected paths', () {
      final good = ProductVtoMetadata.fromProductData(vtoMap())!;
      expect(good.assetsBelongToProduct('mens-oxford-shirt'), isTrue);
      expect(good.assetsBelongToProduct('some-other-id'), isFalse);

      final wrongSlot = ProductVtoMetadata.fromProductData(
        vtoMap(
          overrides: {
            'vtoGarments': {
              'green': assetMap(), // path still says .../garment-blue-v1.jpg
            },
          },
        ),
      )!;
      expect(wrongSlot.assetsBelongToProduct('mens-oxford-shirt'), isFalse);
    });

    test(
      'unknownColorKeys flags keys that are not a ProductColorOption name',
      () {
        final vto = ProductVtoMetadata.fromProductData(
          vtoMap(
            overrides: {
              'vtoGarments': {'blue': assetMap(), 'blooe': assetMap()},
            },
          ),
        )!;
        expect(
          vto.unknownColorKeys({'blue', 'green', 'black'}),
          contains('blooe'),
        );
        expect(
          vto.unknownColorKeys({'blue', 'green', 'black'}),
          isNot(contains('blue')),
        );
      },
    );

    test('copyWith + value semantics', () {
      final a = ProductVtoMetadata.fromProductData(vtoMap())!;
      final b = ProductVtoMetadata.fromProductData(vtoMap())!;
      expect(a, b);
      final c = a.copyWith(garmentCategory: 'outerwear');
      expect(c.garmentCategory, 'outerwear');
      expect(c.garmentsByColor, a.garmentsByColor);
      expect(c == a, isFalse);
    });
  });

  group('ProductVtoMetadata — absent / legacy', () {
    test('no VTO signal yields null (not an error)', () {
      expect(ProductVtoMetadata.fromProductData({'title': 'plain'}), isNull);
      // A legacy-only doc: the pre-9.3 mock string, no typed contract.
      expect(
        ProductVtoMetadata.fromProductData({
          'experienceType': 'virtualTryOn',
          'vtoModelType': 'male',
          'vtoGarmentAssetPath': 'male_jacket.glb',
        }),
        isNull,
      );
      expect(ProductVtoMetadata.validationIssues({'title': 'plain'}), [
        'no Virtual Try-On metadata',
      ]);
      expect(ProductVtoMetadata.validationIssues(null), [
        'no Virtual Try-On metadata',
      ]);
    });

    test('any single vto* signal produces a (diagnosable) object', () {
      final catOnly = ProductVtoMetadata.fromProductData({
        'vtoGarmentCategory': 'top',
      })!;
      expect(catOnly.isRenderable, isFalse);
      expect(
        catOnly.issues,
        contains(
          'no garment asset configured (need a per-colour asset or a default)',
        ),
      );

      final garmentsOnly = ProductVtoMetadata.fromProductData({
        'vtoGarments': {'blue': assetMap()},
      })!;
      expect(garmentsOnly.isRenderable, isFalse);
      expect(garmentsOnly.garmentCategory, '');
    });
  });

  group('ProductVtoMetadata — malformed / unsupported', () {
    test('unsupported garment category', () {
      final vto = ProductVtoMetadata.fromProductData(
        vtoMap(overrides: {'vtoGarmentCategory': 'shoes'}),
      )!;
      expect(vto.isRenderable, isFalse);
      expect(vto.issues.first, contains('garment category must be one of'));
    });

    test('missing contract id', () {
      final data = vtoMap()..remove('vtoContract');
      final vto = ProductVtoMetadata.fromProductData(data)!;
      expect(vto.isRenderable, isFalse);
      expect(vto.issues, contains('vto contract id is missing'));
    });

    test('a broken per-colour asset makes the whole config non-renderable, '
        'with a colour-scoped issue', () {
      final vto = ProductVtoMetadata.fromProductData(
        vtoMap(
          overrides: {
            'vtoGarments': {
              'blue': assetMap(),
              'green': assetMap(overrides: {'sha256': 'bad'}),
            },
          },
        ),
      )!;
      expect(vto.isRenderable, isFalse);
      expect(
        vto.issues.any(
          (i) => i.startsWith('garment "green": ') && i.contains('sha256'),
        ),
        isTrue,
      );
    });

    test('a broken default asset makes the whole config non-renderable', () {
      final vto = ProductVtoMetadata.fromProductData(
        vtoMap(
          overrides: {
            'vtoGarmentDefault': {
              'storagePath': 'products/x/vto/garment-default-v1.jpg',
            },
          },
        ),
      )!;
      expect(vto.isRenderable, isFalse);
      expect(vto.issues.any((i) => i.startsWith('default garment: ')), isTrue);
    });

    test('garbage vtoGarments value (not a map) is ignored, not a crash', () {
      final vto = ProductVtoMetadata.fromProductData({
        'vtoGarmentCategory': 'top',
        'vtoContract': ProductVtoMetadata.currentContract,
        'vtoGarments': {'blue': 'not-a-map', 'green': 42},
      })!;
      expect(vto.garmentsByColor, isEmpty);
      expect(vto.isRenderable, isFalse); // no usable asset
    });
  });

  group('ProductVtoMetadata — provider reference constant (D2)', () {
    test('the Stage-1 selected provider is recorded and unchanged', () {
      // A deliberate anchor: if the provider is ever changed it must be a
      // documented decision, not an accident.
      expect(ProductVtoMetadata.selectedProvider, 'gemini');
      expect(
        ProductVtoMetadata.selectedProviderModel,
        'gemini-2.5-flash-image',
      );
    });

    test('toFirestoreFields never leaks provider/model/credential keys', () {
      final withDefault = ProductVtoMetadata.fromProductData(
        vtoMap(
          overrides: {
            'vtoGarmentDefault': assetMap(
              overrides: {
                'storagePath':
                    'products/mens-oxford-shirt/vto/garment-default-v1.jpg',
              },
            ),
          },
        ),
      )!;
      final fields = withDefault.toFirestoreFields();
      expect(fields.keys.toSet(), {
        'vtoGarmentCategory',
        'vtoContract',
        'vtoGarments',
        'vtoGarmentDefault',
      });
      final blob = fields.toString().toLowerCase();
      for (final banned in [
        'provider',
        'gemini',
        'apikey',
        'api_key',
        'token',
        'secret',
        'credential',
      ]) {
        expect(
          blob.contains(banned),
          isFalse,
          reason: 'must not contain "$banned"',
        );
      }
    });
  });

  // ── Verify-and-harden pass (2026-09-10) ────────────────────────────────────
  group('hardening — cross-product ownership (isRenderableForProduct)', () {
    test('a well-formed but cross-product path is renderable id-agnostically '
        'yet NOT renderableForProduct', () {
      final vto = ProductVtoMetadata.fromProductData(
        vtoMap(
          overrides: {
            'vtoGarments': {
              'blue': assetMap(
                overrides: {
                  // valid shape, but points at a DIFFERENT product
                  'storagePath':
                      'products/some-other-product/vto/garment-blue-v1.jpg',
                },
              ),
            },
          },
        ),
      )!;
      expect(
        vto.isRenderable,
        isTrue,
        reason: 'id-agnostic shape check passes',
      );
      expect(vto.assetsBelongToProduct('mens-oxford-shirt'), isFalse);
      expect(vto.isRenderableForProduct('mens-oxford-shirt'), isFalse);
      // and it does belong to the id it actually names
      expect(vto.isRenderableForProduct('some-other-product'), isTrue);
    });

    test('a per-colour key that disagrees with its own path is rejected', () {
      final vto = ProductVtoMetadata.fromProductData(
        vtoMap(
          overrides: {
            'vtoGarments': {
              'green': assetMap(), // path still says garment-blue-v1.jpg
            },
          },
        ),
      )!;
      expect(vto.isRenderable, isTrue);
      expect(vto.isRenderableForProduct('mens-oxford-shirt'), isFalse);
    });
  });

  group('hardening — strict integer parsing (no silent normalisation)', () {
    test('non-whole version 2.7 is rejected, not truncated to 2', () {
      final a = VtoGarmentAsset.fromMap(assetMap(overrides: {'version': 2.7}))!;
      expect(a.isRenderable, isFalse);
      expect(a.issues, contains('version must be a whole number >= 1'));
    });

    test('string version "2" is rejected', () {
      final a = VtoGarmentAsset.fromMap(assetMap(overrides: {'version': '2'}))!;
      expect(a.isRenderable, isFalse);
    });

    test(
      'whole-valued double 2.0 (how Firestore may store an int) is accepted',
      () {
        final a = VtoGarmentAsset.fromMap(
          assetMap(
            overrides: {
              'version': 3.0,
              'byteSize': 820000.0,
              'width': 1280.0,
              'height': 1600.0,
            },
          ),
        )!;
        expect(a.version, 3);
        expect(a.byteSize, 820000);
        expect(a.isRenderable, isTrue);
      },
    );

    test('non-whole byteSize / width are rejected', () {
      expect(
        VtoGarmentAsset.fromMap(
          assetMap(overrides: {'byteSize': 100.5}),
        )!.isRenderable,
        isFalse,
      );
      expect(
        VtoGarmentAsset.fromMap(
          assetMap(overrides: {'width': 1280.4}),
        )!.isRenderable,
        isFalse,
      );
    });
  });

  group('hardening — malformed sub-entries are diagnosable, never dropped', () {
    for (final garbage in <Object>[<String, dynamic>{}, 'x', 42, <int>[]]) {
      test('a malformed per-colour entry ($garbage) => colour-scoped issue + '
          'non-renderable', () {
        final vto = ProductVtoMetadata.fromProductData(
          vtoMap(
            overrides: {
              'vtoGarments': {'blue': assetMap(), 'green': garbage},
            },
          ),
        )!;
        expect(vto.garmentsByColor.keys, ['blue']);
        expect(vto.malformedGarmentSlots, contains('green'));
        expect(vto.isRenderable, isFalse);
        expect(
          vto.issues.any((i) => i.startsWith('garment "green": ')),
          isTrue,
        );
      });
    }

    test('a malformed vtoGarmentDefault => "default garment" issue + '
        'non-renderable', () {
      final vto = ProductVtoMetadata.fromProductData(
        vtoMap(overrides: {'vtoGarmentDefault': <String, dynamic>{}}),
      )!;
      expect(vto.garmentDefault, isNull);
      expect(vto.garmentDefaultMalformed, isTrue);
      expect(vto.isRenderable, isFalse);
      expect(vto.issues.any((i) => i.startsWith('default garment: ')), isTrue);
    });

    test(
      'vtoGarments that is not a map at all => diagnosable + non-renderable',
      () {
        final vto = ProductVtoMetadata.fromProductData({
          'vtoGarmentCategory': 'top',
          'vtoContract': ProductVtoMetadata.currentContract,
          'vtoGarments': 'oops',
        })!;
        expect(
          vto.malformedGarmentSlots,
          contains('(vtoGarments is not a map)'),
        );
        expect(vto.isRenderable, isFalse);
      },
    );

    test(
      'malformed inputs / parse artifacts are NOT echoed back by toFirestoreFields',
      () {
        final vto = ProductVtoMetadata.fromProductData(
          vtoMap(
            overrides: {
              'vtoGarments': {'blue': assetMap(), 'green': 42},
              'vtoGarmentDefault': <String, dynamic>{},
            },
          ),
        )!;
        // `green` (unparseable) and the malformed default are dropped; only the
        // well-formed `blue` survives, and no malformed*/artifact key appears.
        final fields = vto.toFirestoreFields();
        expect(fields.keys.toSet(), {
          'vtoGarmentCategory',
          'vtoContract',
          'vtoGarments',
        });
        expect((fields['vtoGarments'] as Map).keys, ['blue']);
      },
    );

    test('== / hashCode account for malformed fields', () {
      final broken = ProductVtoMetadata.fromProductData(
        vtoMap(
          overrides: {
            'vtoGarments': {'blue': assetMap(), 'green': 42},
          },
        ),
      )!;
      final clean = ProductVtoMetadata.fromProductData(vtoMap())!;
      expect(broken == clean, isFalse);
      expect(broken.malformedGarmentSlots, isNotEmpty);
    });
  });

  group('hardening — isolated / leftover vto* keys are diagnosable', () {
    test('vtoContract alone produces a non-renderable object, not null', () {
      final vto = ProductVtoMetadata.fromProductData({'vtoContract': 'x'})!;
      expect(vto.isRenderable, isFalse);
      expect(
        vto.issues,
        contains(
          'no garment asset configured (need a per-colour asset or a default)',
        ),
      );
      expect(
        ProductVtoMetadata.validationIssues({'vtoContract': 'x'}),
        isNot(['no Virtual Try-On metadata']),
      );
    });

    test('vtoDisabled alone produces a non-renderable object, not null', () {
      final vto = ProductVtoMetadata.fromProductData({'vtoDisabled': true})!;
      expect(vto.isRenderable, isFalse);
    });

    test('a truly VTO-free doc still yields null', () {
      expect(
        ProductVtoMetadata.fromProductData({
          'title': 't',
          'vtoModelType': 'male',
          'vtoGarmentAssetPath': 'legacy.glb',
        }),
        isNull,
      );
    });
  });

  group('hardening — resolveGarment fails closed', () {
    test('a non-renderable resolved asset returns null', () {
      final vto = ProductVtoMetadata(
        garmentCategory: 'top',
        garmentsByColor: {
          'blue': VtoGarmentAsset.fromMap(assetMap())!.copyWith(sha256: 'bad'),
        },
      );
      expect(vto.resolveGarment('blue'), isNull);
    });

    test(
      'falls through to a renderable default; null when default also broken',
      () {
        final okDefault = ProductVtoMetadata(
          garmentCategory: 'top',
          garmentDefault: VtoGarmentAsset.fromMap(
            assetMap(
              overrides: {
                'storagePath': 'products/x/vto/garment-default-v1.jpg',
              },
            ),
          )!,
        );
        expect(okDefault.resolveGarment('anything'), isNotNull);

        final brokenDefault = ProductVtoMetadata(
          garmentCategory: 'top',
          garmentDefault: VtoGarmentAsset.fromMap(
            assetMap(),
          )!.copyWith(byteSize: -5),
        );
        expect(brokenDefault.resolveGarment('anything'), isNull);
      },
    );
  });

  group('ownedAssetPaths / hasForeignAssetPath (Stage 3 hardening)', () {
    VtoGarmentAsset own(String pid, String slot, {int v = 1}) =>
        VtoGarmentAsset(
          storagePath: 'products/$pid/vto/garment-$slot-v$v.jpg',
          sha256: sha,
          contentType: 'image/jpeg',
          byteSize: 1000,
          width: 900,
          height: 1200,
          version: v,
        );

    test('returns exactly the paths that match their own product + slot', () {
      final vto = ProductVtoMetadata(
        garmentCategory: 'top',
        garmentsByColor: {
          'blue': own('p1', 'blue'),
          'black': own('p1', 'black'),
        },
        garmentDefault: own('p1', 'default'),
      );
      expect(vto.ownedAssetPaths('p1'), {
        'products/p1/vto/garment-blue-v1.jpg',
        'products/p1/vto/garment-black-v1.jpg',
        'products/p1/vto/garment-default-v1.jpg',
      });
      expect(vto.hasForeignAssetPath('p1'), isFalse);
    });

    test('excludes a cross-product path and flags it', () {
      final vto = ProductVtoMetadata(
        garmentCategory: 'top',
        garmentsByColor: {
          'blue': own('p1', 'blue'),
          'black': own('OTHER-PRODUCT', 'black'), // foreign
        },
      );
      expect(vto.ownedAssetPaths('p1'), {
        'products/p1/vto/garment-blue-v1.jpg',
      });
      expect(vto.hasForeignAssetPath('p1'), isTrue);
    });

    test('excludes a wrong-slot / wrong-version path', () {
      final vto = ProductVtoMetadata(
        garmentCategory: 'top',
        garmentsByColor: {
          // key says "blue" but the stored path says "green"
          'blue': own('p1', 'green'),
        },
        // default asset stored at v2 but its version field says v1
        garmentDefault: VtoGarmentAsset(
          storagePath: 'products/p1/vto/garment-default-v2.jpg',
          sha256: sha,
          contentType: 'image/jpeg',
          byteSize: 1000,
          width: 900,
          height: 1200,
          version: 1,
        ),
      );
      expect(vto.ownedAssetPaths('p1'), isEmpty);
      expect(vto.hasForeignAssetPath('p1'), isTrue);
    });

    test('empty metadata → empty owned set, not foreign', () {
      const vto = ProductVtoMetadata(garmentCategory: 'top');
      expect(vto.ownedAssetPaths('p1'), isEmpty);
      expect(vto.hasForeignAssetPath('p1'), isFalse);
    });
  });
}
