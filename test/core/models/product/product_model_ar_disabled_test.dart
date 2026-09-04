import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/product_firestore_mapper.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';

ProductModel _base({
  ProductArMetadata? ar,
  bool disabled = false,
  ProductExperienceType exp = ProductExperienceType.roomAr,
}) => ProductModel(
  id: 'p1',
  sku: 'SKU',
  title: 'T',
  description: 'd',
  categoryId: 'furniture',
  categoryKind: ProductCategory.furniture,
  subcategory: 'sub',
  priceAmount: 100,
  stockQuantity: 1,
  mainImage: const ProductImageRef(path: 'x'),
  experienceType: exp,
  deliveryEstimate: '3-5',
  addedDate: DateTime(2026, 1, 1),
  arMetadata: ar,
  arModelDisabled: disabled,
);

final _validAr = ProductArMetadata(
  storagePath: 'products/p1/ar/model-v1.glb',
  modelVersion: '1',
  sha256: 'a' * 64,
  widthM: 0.7,
  depthM: 0.72,
  heightM: 0.82,
);

void main() {
  test('Phase 9.2 R16 — arModelDisabled folds into hasRenderableArModel', () {
    expect(_base(ar: _validAr).hasRenderableArModel, isTrue);
    expect(_base(ar: _validAr).hasDisabledArModel, isFalse);

    final off = _base(ar: _validAr, disabled: true);
    expect(off.hasRenderableArModel, isFalse);
    expect(off.hasDisabledArModel, isTrue);

    // not opted into roomAr → neither
    final notAr = _base(
      ar: _validAr,
      disabled: true,
      exp: ProductExperienceType.none,
    );
    expect(notAr.hasRenderableArModel, isFalse);
    expect(notAr.hasDisabledArModel, isFalse);
  });

  test('clearing the model contract also clears the disabled flag', () {
    final cleared = _base(
      ar: _validAr,
      disabled: true,
    ).copyWith(clearArMetadata: true);
    expect(cleared.arMetadata, isNull);
    expect(cleared.arModelDisabled, isFalse);
  });

  test('mapper: arModelDisabled round-trips and is omitted when false', () {
    final onMap = _base(ar: _validAr).toFirestoreMap();
    expect(onMap.containsKey('arModelDisabled'), isFalse);

    final offMap = _base(ar: _validAr, disabled: true).toFirestoreMap();
    expect(offMap['arModelDisabled'], true);

    final readBack = productModelFromFirestore('p1', {
      ...offMap,
      'addedDate': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });
    expect(readBack.arModelDisabled, isTrue);
    expect(readBack.hasRenderableArModel, isFalse);
  });

  test(
    'mapper: a pre-R16 document with no arModelDisabled key reads false',
    () {
      final doc = _base(ar: _validAr).toFirestoreMap()
        ..remove('arModelDisabled')
        ..['addedDate'] = Timestamp.fromDate(DateTime(2026, 1, 1));
      expect(productModelFromFirestore('p1', doc).arModelDisabled, isFalse);
    },
  );
}
