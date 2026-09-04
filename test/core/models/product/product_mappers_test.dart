import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_mappers.dart';
import 'package:twin_ar/core/models/product/product_model.dart';

ProductModel _product({required ProductImageRef mainImage}) => ProductModel(
  id: 'p1',
  sku: 'SKU-1',
  title: 'Test Product',
  description: 'A product',
  categoryId: 'furniture',
  categoryKind: ProductCategory.furniture,
  subcategory: 'Chairs',
  priceAmount: 1000,
  stockQuantity: 5,
  mainImage: mainImage,
  experienceType: ProductExperienceType.none,
  deliveryEstimate: '3-5 days',
  addedDate: DateTime(2026, 1, 1),
);

void main() {
  group('ProductModelMappers.toSummaryModel - Phase 8.7 source-awareness', () {
    test('an asset-sourced mainImage maps to imageSource.asset', () {
      final summary = _product(
        mainImage: const ProductImageRef(path: 'assets/a.png'),
      ).toSummaryModel();

      expect(summary.imageAssetPath, 'assets/a.png');
      expect(summary.imageSource, ProductImageSource.asset);
      expect(summary.image.source, ProductImageSource.asset);
    });

    test('a network-sourced mainImage maps to imageSource.network', () {
      final summary = _product(
        mainImage: const ProductImageRef(
          path: 'https://firebasestorage.example/a.jpg',
          source: ProductImageSource.network,
        ),
      ).toSummaryModel();

      expect(summary.imageSource, ProductImageSource.network);
      expect(summary.image.path, 'https://firebasestorage.example/a.jpg');
    });

    test('a file-sourced mainImage maps to imageSource.file', () {
      final summary = _product(
        mainImage: const ProductImageRef(
          path: '/local/staged.jpg',
          source: ProductImageSource.file,
        ),
      ).toSummaryModel();

      expect(summary.imageSource, ProductImageSource.file);
    });

    test(
      'toCatalogModel/toDetailModel forward the same source-aware summary',
      () {
        final product = _product(
          mainImage: const ProductImageRef(
            path: 'https://firebasestorage.example/a.jpg',
            source: ProductImageSource.network,
          ),
        );

        expect(
          product.toCatalogModel().summary.imageSource,
          ProductImageSource.network,
        );
        expect(
          product.toDetailModel().summary.imageSource,
          ProductImageSource.network,
        );
      },
    );
  });

  group('ProductModelMappers.toDetailModel - Phase 9.2 R12 AR contract', () {
    const ar = ProductArMetadata(
      storagePath: 'products/luna-accent-chair/ar/model-v1.glb',
      modelVersion: '1',
      sha256:
          'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
      widthM: 0.70,
      depthM: 0.72,
      heightM: 0.82,
    );

    test('the detail model now carries arMetadata through unchanged', () {
      final detail =
          _product(mainImage: const ProductImageRef(path: 'assets/a.png'))
              .copyWith(
                experienceType: ProductExperienceType.roomAr,
                arMetadata: ar,
              )
              .toDetailModel();

      expect(detail.arMetadata, ar);
      expect(detail.hasRenderableArModel, isTrue);
    });

    test('a Room-AR product with no contract is not launch-eligible', () {
      final detail = _product(
        mainImage: const ProductImageRef(path: 'assets/a.png'),
      ).copyWith(experienceType: ProductExperienceType.roomAr).toDetailModel();

      expect(detail.arMetadata, isNull);
      expect(detail.isRoomArEnabled, isTrue);
      expect(detail.hasRenderableArModel, isFalse);
    });

    test('a non-AR product is unaffected', () {
      final detail = _product(
        mainImage: const ProductImageRef(path: 'assets/a.png'),
      ).toDetailModel();
      expect(detail.arMetadata, isNull);
      expect(detail.hasRenderableArModel, isFalse);
    });
  });
}
