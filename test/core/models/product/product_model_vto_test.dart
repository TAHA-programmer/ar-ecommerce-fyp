import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/product_firestore_mapper.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_mappers.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_vto_metadata.dart';
import 'package:twin_ar/core/models/product/product_vto_model_type.dart';

final _sha = '0123456789abcdef' * 4; // 64 lowercase hex chars

VtoGarmentAsset _asset(String productId, String slot, {int version = 1}) =>
    VtoGarmentAsset(
      storagePath: 'products/$productId/vto/garment-$slot-v$version.jpg',
      sha256: _sha,
      contentType: 'image/jpeg',
      byteSize: 820000,
      width: 1280,
      height: 1600,
      version: version,
    );

ProductModel _product({
  ProductExperienceType exp = ProductExperienceType.virtualTryOn,
  ProductVtoMetadata? vto,
  bool vtoDisabled = false,
  Set<ProductColorOption> colors = const {ProductColorOption.blue},
  ProductVtoModelType? modelType = ProductVtoModelType.male,
}) => ProductModel(
  id: 'vp1',
  sku: 'SKU',
  title: 'Shirt',
  description: 'd',
  categoryId: 'clothing',
  categoryKind: ProductCategory.clothing,
  subcategory: 'Shirts',
  priceAmount: 5000,
  stockQuantity: 3,
  mainImage: const ProductImageRef(path: 'x'),
  experienceType: exp,
  vtoModelType: modelType,
  availableColors: colors,
  deliveryEstimate: '3-5',
  addedDate: DateTime(2026, 1, 1),
  vtoMetadata: vto,
  vtoDisabled: vtoDisabled,
);

ProductVtoMetadata _vto({
  String category = 'top',
  Map<String, VtoGarmentAsset>? byColor,
  VtoGarmentAsset? fallback,
}) => ProductVtoMetadata(
  garmentCategory: category,
  garmentsByColor: byColor ?? {'blue': _asset('vp1', 'blue')},
  garmentDefault: fallback,
);

void main() {
  group('ProductModel.hasRenderableVtoAsset', () {
    test(
      'true: virtualTryOn + renderable config + not disabled + colour covered',
      () {
        final p = _product(vto: _vto());
        expect(p.vtoMetadata!.isRenderable, isTrue);
        expect(p.hasRenderableVtoAsset, isTrue);
        expect(p.hasDisabledVtoAsset, isFalse);
      },
    );

    test('false: admin switched the entry point off (config retained)', () {
      final p = _product(vto: _vto(), vtoDisabled: true);
      expect(p.hasRenderableVtoAsset, isFalse);
      expect(p.hasDisabledVtoAsset, isTrue);
    });

    test('false: product does not opt into VTO', () {
      final p = _product(exp: ProductExperienceType.none, vto: _vto());
      expect(p.hasRenderableVtoAsset, isFalse);
      expect(p.hasDisabledVtoAsset, isFalse);
    });

    test('false: no VTO metadata at all (every current seed product)', () {
      final p = _product(vto: null);
      expect(p.hasRenderableVtoAsset, isFalse);
      expect(p.isVirtualTryOnEnabled, isTrue);
    });

    test(
      'false: a colour the product sells has no asset and there is no default',
      () {
        final p = _product(
          colors: {ProductColorOption.blue, ProductColorOption.green},
          vto: _vto(byColor: {'blue': _asset('vp1', 'blue')}),
        );
        // config is structurally renderable...
        expect(p.vtoMetadata!.isRenderable, isTrue);
        // ...but green does not resolve.
        expect(p.hasRenderableVtoAsset, isFalse);
      },
    );

    test(
      'true: an uncovered colour is rescued by the product-wide default',
      () {
        final p = _product(
          colors: {ProductColorOption.blue, ProductColorOption.green},
          vto: _vto(
            byColor: {'blue': _asset('vp1', 'blue')},
            fallback: _asset('vp1', 'default'),
          ),
        );
        expect(p.hasRenderableVtoAsset, isTrue);
        expect(
          p.vtoGarmentForColor(ProductColorOption.green)!.storagePath,
          contains('garment-default'),
        );
        expect(
          p.vtoGarmentForColor(ProductColorOption.blue)!.storagePath,
          contains('garment-blue'),
        );
      },
    );

    test('false: config present but non-renderable (broken asset)', () {
      final broken = ProductVtoMetadata(
        garmentCategory: 'top',
        garmentsByColor: {
          'blue': _asset('vp1', 'blue').copyWith(sha256: 'bad'),
        },
      );
      final p = _product(vto: broken);
      expect(p.vtoMetadata!.isRenderable, isFalse);
      expect(p.hasRenderableVtoAsset, isFalse);
      // hasDisabledVtoAsset also requires a *renderable* config.
      expect(
        _product(vto: broken, vtoDisabled: true).hasDisabledVtoAsset,
        isFalse,
      );
    });

    test('no colours configured: falls back to requiring a default asset', () {
      expect(
        _product(
          colors: const {},
          vto: _vto(byColor: const {}, fallback: _asset('vp1', 'default')),
        ).hasRenderableVtoAsset,
        isTrue,
      );
      expect(
        _product(
          colors: const {},
          vto: _vto(byColor: {'blue': _asset('vp1', 'blue')}),
        ).hasRenderableVtoAsset,
        isFalse,
      );
    });
  });

  group('ProductModel.copyWith — VTO', () {
    test(
      'clearVtoMetadata removes the config AND resets the disabled switch',
      () {
        final cleared = _product(
          vto: _vto(),
          vtoDisabled: true,
        ).copyWith(clearVtoMetadata: true);
        expect(cleared.vtoMetadata, isNull);
        expect(cleared.vtoDisabled, isFalse);
        expect(cleared.hasRenderableVtoAsset, isFalse);
      },
    );

    test('setting vtoMetadata / vtoDisabled without the clear flag', () {
      final base = _product(vto: null);
      final withVto = base.copyWith(vtoMetadata: _vto(), vtoDisabled: true);
      expect(withVto.vtoMetadata, isNotNull);
      expect(withVto.vtoDisabled, isTrue);
      // untouched fields survive
      expect(withVto.id, base.id);
      expect(withVto.experienceType, base.experienceType);
    });
  });

  group('Firestore mapper — VTO round-trip & backward compatibility', () {
    Map<String, dynamic> readable(Map<String, dynamic> m) => {
      ...m,
      'addedDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
    };

    test(
      'a full VTO contract round-trips through toFirestoreMap / fromFirestore',
      () {
        final original = _product(
          colors: {ProductColorOption.blue, ProductColorOption.green},
          vto: _vto(
            byColor: {
              'blue': _asset('vp1', 'blue'),
              'green': _asset('vp1', 'green'),
            },
            fallback: _asset('vp1', 'default'),
          ),
        );
        final map = original.toFirestoreMap();
        expect(map['vtoGarmentCategory'], 'top');
        expect(map['vtoContract'], ProductVtoMetadata.currentContract);
        expect(
          (map['vtoGarments'] as Map).keys,
          containsAll(['blue', 'green']),
        );
        expect(map.containsKey('vtoGarmentDefault'), isTrue);
        expect(map.containsKey('vtoDisabled'), isFalse);

        final restored = productModelFromFirestore('vp1', readable(map));
        expect(restored.vtoMetadata, original.vtoMetadata);
        expect(restored.vtoDisabled, isFalse);
        expect(restored.hasRenderableVtoAsset, isTrue);
      },
    );

    test('vtoDisabled is written only when true and reads back', () {
      final off = _product(vto: _vto(), vtoDisabled: true).toFirestoreMap();
      expect(off['vtoDisabled'], true);
      final restored = productModelFromFirestore('vp1', readable(off));
      expect(restored.vtoDisabled, isTrue);
      expect(restored.hasRenderableVtoAsset, isFalse);
      expect(restored.hasDisabledVtoAsset, isTrue);
    });

    test(
      'toFirestoreMap omits every vto* contract key when vtoMetadata is null',
      () {
        final map = _product(vto: null).toFirestoreMap();
        for (final k in const [
          'vtoGarmentCategory',
          'vtoContract',
          'vtoGarments',
          'vtoGarmentDefault',
          'vtoDisabled',
        ]) {
          expect(map.containsKey(k), isFalse, reason: k);
        }
        // legacy mock string is still emitted (inert, backward-compat)
        expect(map.containsKey('vtoGarmentAssetPath'), isTrue);
      },
    );

    test(
      'a pre-Stage-3 document (no vto* keys) reads null / false / ineligible',
      () {
        final doc = readable({
          'sku': 'S',
          'title': 'Legacy shirt',
          'experienceType': 'virtualTryOn',
          'vtoModelType': 'female',
          'vtoGarmentAssetPath': 'female_hoodie.glb',
          'availableColors': ['blue'],
          'publicationStatus': 'published',
        });
        final p = productModelFromFirestore('legacy', doc);
        expect(p.isVirtualTryOnEnabled, isTrue);
        expect(p.vtoMetadata, isNull);
        expect(p.vtoDisabled, isFalse);
        expect(p.hasRenderableVtoAsset, isFalse);
        expect(p.vtoGarmentAssetPath, 'female_hoodie.glb');
      },
    );

    test(
      'a present-but-incomplete config survives a read as non-renderable',
      () {
        final doc = readable({
          'experienceType': 'virtualTryOn',
          'availableColors': ['blue'],
          'publicationStatus': 'published',
          'vtoGarmentCategory': 'top',
          // no vtoGarments / vtoContract
        });
        final p = productModelFromFirestore('incomplete', doc);
        expect(p.vtoMetadata, isNotNull);
        expect(p.vtoMetadata!.isRenderable, isFalse);
        expect(p.hasRenderableVtoAsset, isFalse);
      },
    );
  });

  group('backward compatibility — existing catalogue is undisturbed', () {
    test(
      'every seed product: no VTO contract, VTO-ineligible, but tryOnEnabled '
      'summary flag and experienceType are UNCHANGED',
      () {
        for (final p in MockCommerceDatabase().products) {
          expect(p.vtoMetadata, isNull, reason: p.id);
          expect(p.vtoDisabled, isFalse, reason: p.id);
          expect(p.hasRenderableVtoAsset, isFalse, reason: p.id);
          // The Stage-2 change must NOT alter what Home/badges show today.
          expect(
            p.toSummaryModel().tryOnEnabled,
            p.experienceType == ProductExperienceType.virtualTryOn,
            reason: p.id,
          );
        }
      },
    );

    test(
      'toDetailModel carries the VTO contract through with matching getters',
      () {
        final p = _product(vto: _vto());
        final d = p.toDetailModel();
        expect(d.vtoMetadata, p.vtoMetadata);
        expect(d.vtoDisabled, p.vtoDisabled);
        expect(d.hasRenderableVtoAsset, p.hasRenderableVtoAsset);
        expect(d.hasDisabledVtoAsset, p.hasDisabledVtoAsset);
        expect(
          d.vtoGarmentForColor(ProductColorOption.blue)!.storagePath,
          p.vtoGarmentForColor(ProductColorOption.blue)!.storagePath,
        );

        final none = _product(
          exp: ProductExperienceType.none,
          vto: null,
        ).toDetailModel();
        expect(none.vtoMetadata, isNull);
        expect(none.hasRenderableVtoAsset, isFalse);
      },
    );
  });

  // ── Verify-and-harden pass (2026-09-10) ─────────────────────────────────────
  group('hardening — cross-product garment path is NOT eligible', () {
    ProductVtoMetadata crossProductVto() => ProductVtoMetadata(
      garmentCategory: 'top',
      // valid shape, right colour key, but the path names a different product
      garmentsByColor: {'blue': _asset('a-different-product', 'blue')},
    );

    test(
      'ProductModel.hasRenderableVtoAsset is false for a cross-product path',
      () {
        final p = _product(vto: crossProductVto());
        expect(
          p.vtoMetadata!.isRenderable,
          isTrue,
          reason: 'shape is valid, only ownership is wrong',
        );
        expect(p.vtoMetadata!.isRenderableForProduct('vp1'), isFalse);
        expect(p.hasRenderableVtoAsset, isFalse);
        // and a disabled cross-product config reads as broken, not "disabled"
        expect(
          _product(
            vto: crossProductVto(),
            vtoDisabled: true,
          ).hasDisabledVtoAsset,
          isFalse,
        );
      },
    );

    test('ProductDetailModel mirrors it (via toDetailModel)', () {
      final d = _product(vto: crossProductVto()).toDetailModel();
      expect(d.hasRenderableVtoAsset, isFalse);
    });

    test('the same assets under this product ARE eligible', () {
      final p = _product(
        vto: ProductVtoMetadata(
          garmentCategory: 'top',
          garmentsByColor: {'blue': _asset('vp1', 'blue')},
        ),
      );
      expect(p.hasRenderableVtoAsset, isTrue);
    });
  });

  group('hardening — mapper never throws on a corrupt vtoDisabled', () {
    Map<String, dynamic> readable(Map<String, dynamic> m) => {
      ...m,
      'addedDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
    };

    for (final corrupt in <Object>[
      1,
      0,
      'true',
      'false',
      <String, dynamic>{},
      <int>[],
    ]) {
      test('vtoDisabled: $corrupt reads as true (fail closed), no throw', () {
        final base = _product(vto: _vto()).toFirestoreMap();
        final doc = readable({...base, 'vtoDisabled': corrupt});
        late ProductModel p;
        expect(
          () => p = productModelFromFirestore('vp1', doc),
          returnsNormally,
        );
        expect(p.vtoDisabled, isTrue);
        expect(p.hasRenderableVtoAsset, isFalse);
      });
    }

    test('a real bool still round-trips; absent still reads false', () {
      final on = _product(vto: _vto()).toFirestoreMap();
      expect(
        productModelFromFirestore(
          'vp1',
          readable({...on, 'vtoDisabled': false}),
        ).vtoDisabled,
        isFalse,
      );
      expect(
        productModelFromFirestore(
          'vp1',
          readable({...on, 'vtoDisabled': true}),
        ).vtoDisabled,
        isTrue,
      );
      on.remove('vtoDisabled');
      expect(
        productModelFromFirestore('vp1', readable(on)).vtoDisabled,
        isFalse,
      );
    });
  });

  group('hardening — corrupt / isolated vto* fields read fail-closed', () {
    Map<String, dynamic> readable(Map<String, dynamic> m) => {
      ...m,
      'addedDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
    };

    test('a garbage garment entry => vtoMetadata non-null, non-renderable, '
        'ineligible, and the bad slot is named', () {
      final doc = readable({
        'experienceType': 'virtualTryOn',
        'availableColors': ['blue'],
        'publicationStatus': 'published',
        'vtoGarmentCategory': 'top',
        'vtoContract': ProductVtoMetadata.currentContract,
        'vtoGarments': {'blue': 'not-a-map'},
      });
      final p = productModelFromFirestore('vp1', doc);
      expect(p.vtoMetadata, isNotNull);
      expect(p.vtoMetadata!.isRenderable, isFalse);
      expect(p.vtoMetadata!.malformedGarmentSlots, contains('blue'));
      expect(p.hasRenderableVtoAsset, isFalse);
    });

    test('vtoContract alone => vtoMetadata non-null, ineligible', () {
      final p = productModelFromFirestore(
        'vp1',
        readable({
          'experienceType': 'virtualTryOn',
          'publicationStatus': 'published',
          'vtoContract': 'x',
        }),
      );
      expect(p.vtoMetadata, isNotNull);
      expect(p.hasRenderableVtoAsset, isFalse);
    });

    test('seed products remain entirely unaffected by the hardening', () {
      for (final sp in MockCommerceDatabase().products) {
        final restored = productModelFromFirestore(sp.id, {
          ...sp.toFirestoreMap(),
          'addedDate': Timestamp.fromDate(sp.addedDate),
        });
        expect(restored.vtoMetadata, isNull, reason: sp.id);
        expect(restored.vtoDisabled, isFalse, reason: sp.id);
        expect(restored.hasRenderableVtoAsset, isFalse, reason: sp.id);
      }
    });
  });
}
