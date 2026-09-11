import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_size.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/core/models/product/product_vto_metadata.dart';
import 'package:twin_ar/core/models/product/product_vto_model_type.dart';
import 'package:twin_ar/features/product_details/models/product_detail_model.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';

/// Shared Phase 9.3 Stage 5 test fixtures. The shared app-wide mock catalogue
/// (`MockProductDetailsRepository`) has no `vtoMetadata` for any product
/// (Stage 2/3 never seeded one), so `hasRenderableVtoAsset` is always `false`
/// against it — every Stage 5 test that needs an ELIGIBLE product builds its
/// own fixture here instead, exactly the same approach Stage 2's own test
/// suite (`product_vto_metadata_test.dart`) used.
const String kEligibleVtoProductId = 'vto-test-shirt';

VtoGarmentAsset _asset(String productId, String slot, {int version = 1}) =>
    VtoGarmentAsset(
      storagePath: 'products/$productId/vto/garment-$slot-v$version.jpg',
      sha256: 'a' * 64,
      contentType: 'image/jpeg',
      byteSize: 1024,
      width: 1000,
      height: 1200,
      version: version,
    );

/// An eligible (`hasRenderableVtoAsset == true`) clothing product: blue +
/// black colours, S/M/L sizes, a renderable garment asset for every colour.
ProductDetailModel buildEligibleVtoProduct({
  String id = kEligibleVtoProductId,
  int stockQuantity = 10,
  List<ProductColorOption> colors = const [
    ProductColorOption.blue,
    ProductColorOption.black,
  ],
  List<ProductSize> sizes = const [ProductSize.s, ProductSize.m, ProductSize.l],
  ProductColorOption? defaultColor = ProductColorOption.blue,
  ProductSize? defaultSize = ProductSize.m,
  bool vtoDisabled = false,
  Set<ProductColorOption> missingAssetForColors = const {},
}) {
  final garments = <String, VtoGarmentAsset>{
    for (final c in colors)
      if (!missingAssetForColors.contains(c)) c.name: _asset(id, c.name),
  };

  return ProductDetailModel(
    summary: ProductSummaryModel(
      id: id,
      title: 'Test Shirt',
      imageAssetPath: 'assets/images/placeholder.png',
      currentPrice: '\$22.00',
      tryOnEnabled: true,
    ),
    stockQuantity: stockQuantity,
    categoryId: 'clothing',
    categoryKind: ProductCategory.clothing,
    experienceType: ProductExperienceType.virtualTryOn,
    vtoModelType: ProductVtoModelType.male,
    vtoMetadata: ProductVtoMetadata(
      garmentCategory: 'top',
      garmentsByColor: garments,
    ),
    vtoDisabled: vtoDisabled,
    subcategory: 'Shirts',
    gallery: const [],
    description: 'A test shirt.',
    availableColors: colors,
    availableSizes: sizes,
    defaultColor: defaultColor,
    defaultSize: defaultSize,
    specifications: const [],
    deliveryEstimate: '3-5 Business Days',
  );
}

/// A product with `experienceType != virtualTryOn` — never eligible.
ProductDetailModel buildNonVtoProduct({String id = 'non-vto-product'}) {
  return ProductDetailModel(
    summary: ProductSummaryModel(
      id: id,
      title: 'Non VTO Product',
      imageAssetPath: 'assets/images/placeholder.png',
      currentPrice: '\$10.00',
    ),
    stockQuantity: 5,
    categoryId: 'furniture',
    categoryKind: ProductCategory.furniture,
    experienceType: ProductExperienceType.none,
    subcategory: 'Chairs',
    gallery: const [],
    description: 'Not a try-on product.',
    availableColors: const [],
    availableSizes: const [],
    specifications: const [],
    deliveryEstimate: '3-5 Business Days',
  );
}

/// Minimal, fully-controllable [ProductDetailsRepository] — returns
/// [product] for [productId], or throws for any other id.
class FakeVtoProductDetailsRepository implements ProductDetailsRepository {
  final ProductDetailModel product;
  final String productId;
  final Object? errorToThrow;

  FakeVtoProductDetailsRepository({
    required this.product,
    required this.productId,
    this.errorToThrow,
  });

  @override
  Future<ProductDetailModel> getProductDetails(String id) async {
    if (errorToThrow != null) throw errorToThrow!;
    if (id != productId) {
      throw StateError('Unknown product id: $id');
    }
    return product;
  }
}
