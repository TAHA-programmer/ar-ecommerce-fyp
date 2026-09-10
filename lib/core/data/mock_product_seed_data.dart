import '../constants/app_assets.dart';
import '../models/product/product_ar_metadata.dart';
import '../models/product/product_category.dart';
import '../models/product/product_color_option.dart';
import '../models/product/product_experience_type.dart';
import '../models/product/product_model.dart';
import '../models/product/product_image_ref.dart';
import '../models/product/product_size.dart';
import '../models/product/product_specification.dart';
import '../models/product/product_vto_model_type.dart';

/// Phase 9.2 R13/R14 — the production Room-AR metadata for the four
/// physically-approved products, baked into the canonical mock so a reseed
/// carries it. **Must stay byte-identical to
/// `lib/features/room_ar/room_ar_product_manifest.dart`** (a test locks the
/// two together). Storage paths point at `products/{id}/ar/model-v1.glb`,
/// uploaded + physically approved on 2026-08-31 (tracker §2.11).
///
/// `final`, not `const` — the Phase 9.2 coverage-expansion groups below use
/// `for` loops over shared-design id lists, which Dart disallows inside a
/// const collection literal. Every individual [ProductArMetadata] value is
/// still a `const` object. Kept in lockstep with the manifest by
/// `room_ar_product_manifest_test.dart`'s byte-identical check.
final Map<String, ProductArMetadata> kRoomArProductMetadata = {
  'luna-accent-chair': const ProductArMetadata(
    storagePath: 'products/luna-accent-chair/ar/model-v1.glb',
    modelVersion: '1',
    sha256: 'd67c68f823d06881ec1aabf7f8ca6f0128f1016483ea0307f5c2ecef66b3cf94',
    widthM: 0.70,
    depthM: 0.72,
    heightM: 0.82,
  ),
  'glass-coffee-table': const ProductArMetadata(
    storagePath: 'products/glass-coffee-table/ar/model-v1.glb',
    modelVersion: '1',
    sha256: 'd10f32a7373d84031d3e51b8e9770610f514f62fa56110608852f1640ab7a727',
    widthM: 0.90,
    depthM: 0.90,
    heightM: 0.42,
  ),
  'modern-table-lamp': const ProductArMetadata(
    storagePath: 'products/modern-table-lamp/ar/model-v1.glb',
    modelVersion: '1',
    sha256: 'ee417ead58e72de9518358288f089bad272779c190125e01ac372fcfc16bb565',
    widthM: 0.20,
    depthM: 0.20,
    heightM: 0.45,
  ),
  'luna-3-seater-sofa': const ProductArMetadata(
    storagePath: 'products/luna-3-seater-sofa/ar/model-v1.glb',
    modelVersion: '1',
    sha256: 'efd400046b265fd49d8d2b0382d378d230d625cb879740a3ef0697ca86c0d187',
    widthM: 2.65,
    depthM: 1.65,
    heightM: 0.82,
  ),

  // ── Phase 9.2 coverage-expansion (tracker §15, 2026-09-05) ───────────────
  'velvet-armchair': const ProductArMetadata(
    storagePath: 'products/velvet-armchair/ar/model-v1.glb',
    modelVersion: '1',
    sha256: '9909929fdc84adf526127887ab782805bee0ff6863c04e0dd1510a4264f8a09e',
    widthM: 0.72,
    depthM: 0.76,
    heightM: 0.78,
  ),
  'wooden-console': const ProductArMetadata(
    storagePath: 'products/wooden-console/ar/model-v1.glb',
    modelVersion: '1',
    sha256: 'b22ac85b25cac2b4924e04793701c95907c36474bb04df7c4aa9ddda51e03433',
    widthM: 1.80,
    depthM: 0.42,
    heightM: 0.72,
  ),
  'marble-side-table': const ProductArMetadata(
    storagePath: 'products/marble-side-table/ar/model-v1.glb',
    modelVersion: '1',
    sha256: '287b8bb97b3bff21de651b49dbb46024be0462fc2ea3e49c6a08964f79b9b7b3',
    widthM: 0.46,
    depthM: 0.46,
    heightM: 0.53,
  ),
  // Beige AR Rug — one shared design, 7 listing ids.
  for (final id in [
    'beige-ar-in-stock-5',
    'beige-ar-in-stock-7',
    'beige-ar-in-stock-11',
    'beige-ar-in-stock-13',
    'beige-ar-in-stock-17',
    'beige-ar-in-stock-19',
    'beige-ar-in-stock-23',
  ])
    id: ProductArMetadata(
      storagePath: 'products/$id/ar/model-v1.glb',
      modelVersion: '1',
      sha256:
          'd21f1adaf04708ff96976282fa7543814c9718028a3297fe392b0847766837e5',
      widthM: 2.00,
      depthM: 1.35,
      heightM: 0.012,
    ),
  // Beige AR Sofa — one shared design, 8 listing ids.
  for (final id in [
    'beige-ar-in-stock-2',
    'beige-ar-in-stock-4',
    'beige-ar-in-stock-8',
    'beige-ar-in-stock-10',
    'beige-ar-in-stock-14',
    'beige-ar-in-stock-16',
    'beige-ar-in-stock-20',
    'beige-ar-in-stock-22',
  ])
    id: ProductArMetadata(
      storagePath: 'products/$id/ar/model-v1.glb',
      modelVersion: '1',
      sha256:
          '5dfc2a86ea7a9c66ca4190179a31e1d2f2b28c9829cbd9b2240b9284c7db2a84',
      widthM: 2.50,
      depthM: 1.60,
      heightM: 0.70,
    ),
  // Beige AR Vase — one shared design, 8 listing ids.
  for (final id in [
    'beige-ar-in-stock-3',
    'beige-ar-in-stock-6',
    'beige-ar-in-stock-9',
    'beige-ar-in-stock-12',
    'beige-ar-in-stock-15',
    'beige-ar-in-stock-18',
    'beige-ar-in-stock-21',
    'beige-ar-in-stock-24',
  ])
    id: ProductArMetadata(
      storagePath: 'products/$id/ar/model-v1.glb',
      modelVersion: '1',
      sha256:
          'cf8c32bab30e43ca138fd07b5aca50a792389d91228aaacb05cb09321989295d',
      widthM: 0.15,
      depthM: 0.15,
      heightM: 0.20,
    ),
};

/// The canonical mock product catalog (50 products total; `minimalist-bedroom-set`
/// was permanently removed 2026-09-09 — see `18_ROOM_AR_PRODUCT_COVERAGE_MATRIX.md`,
/// which still cites the pre-removal count of 51), as a plain
/// data-construction function with zero Flutter/Firestore imports (only
/// [ProductModel] and its own plain-Dart dependencies).
///
/// Extracted out of [MockCommerceDatabase] (Phase 8.5) specifically so the
/// developer-only `tool/export_product_seed.dart` script can reuse this
/// exact data under a plain `dart run` - which cannot compile anything that
/// transitively imports `package:flutter/...` (needs `dart:ui`, only
/// available under the full Flutter engine, e.g. `flutter test`/`flutter
/// run`). [MockCommerceDatabase] itself calls this function in its
/// constructor - this is a pure relocation, not a behavior change; the
/// generated products are byte-for-byte identical to before this file
/// existed.
List<ProductModel> buildMockProductSeedData() {
  final products = <ProductModel>[];
  var skuCounter = 1;

  String generateSku(ProductCategory category) {
    final prefix = category.name.substring(0, 3).toUpperCase();
    final number = skuCounter.toString().padLeft(3, '0');
    skuCounter++;
    return 'TWA-$prefix-$number';
  }

  ProductModel buildExplicit({
    required String id,
    required String title,
    required String asset,
    required ProductCategory category,
    required ProductExperienceType exp,
    required int price,
    int? originalPrice,
    ProductVtoModelType? vtoModelType,
    required String subcategory,
    List<ProductSpecification> specs = const [],
    double rating = 4.5,
    int reviewCount = 100,
    bool isBestSeller = false,
    bool isFeatured = false,
    bool isNewArrival = false,
    bool isPopularFurniture = false,
    bool isRecentlyViewed = false,
    bool showInCatalog = false,
    String? description,
    ProductArMetadata? arMetadata,
  }) {
    return ProductModel(
      id: id,
      sku: generateSku(category),
      title: title,
      description:
          description ??
          (category == ProductCategory.clothing
              ? 'A stylish and comfortable piece perfect for any occasion. Designed with premium materials for a great fit.'
              : 'Elevate your space with this beautiful and functional piece. Crafted with attention to detail and high-quality materials.'),
      // The 5 canonical mock categories are seeded with categoryId == the
      // enum name (see category_seed_data.dart), so this reuse is exact.
      categoryId: category.name,
      categoryKind: category,
      subcategory: subcategory,
      priceAmount: price,
      originalPriceAmount: originalPrice,
      stockQuantity: 20, // Default generous stock
      showInCatalog: showInCatalog,
      mainImage: ProductImageRef(path: asset),
      galleryMedia: [
        ProductImageRef(path: asset),
        ProductImageRef(path: asset),
        ProductImageRef(path: asset),
        ProductImageRef(path: asset),
        if (category != ProductCategory.clothing) ProductImageRef(path: asset),
      ],
      experienceType: exp,
      vtoModelType: vtoModelType,
      availableColors: const {ProductColorOption.black},
      defaultColor: ProductColorOption.black,
      availableSizes: category == ProductCategory.clothing
          ? const {ProductSize.m, ProductSize.l}
          : const {},
      defaultSize: category == ProductCategory.clothing ? ProductSize.m : null,
      specifications: specs,
      deliveryEstimate: '3 - 5 Days',
      addedDate: DateTime.now().subtract(const Duration(days: 10)),
      rating: rating,
      reviewCount: reviewCount,
      // Metadata used by mock home repo to find these products without needing hardcoded lists
      popularityScore: isBestSeller || isPopularFurniture ? 100 : 50,
      recommendationRank: isFeatured ? 10 : (isNewArrival ? 20 : 50),
      arMetadata: arMetadata,
    );
  }

  ProductModel buildExploreItem({
    required String id,
    required String title,
    required String asset,
    required ProductCategory category,
    required ProductExperienceType exp,
    ProductVtoModelType? vtoModelType,
    required int price,
    required bool inStock,
    required Set<ProductColorOption> colors,
    required double rating,
    required int reviewCount,
    required int recommendationRank,
    required DateTime addedDate,
    required int popularityScore,
    ProductArMetadata? arMetadata,
  }) {
    return ProductModel(
      id: id,
      sku: generateSku(category),
      title: title,
      description: category == ProductCategory.clothing
          ? 'A stylish and comfortable piece perfect for any occasion. Designed with premium materials for a great fit.'
          : 'Elevate your space with this beautiful and functional piece. Crafted with attention to detail and high-quality materials.',
      categoryId: category.name,
      categoryKind: category,
      subcategory: category == ProductCategory.clothing ? 'Outfits' : '',
      priceAmount: price,
      stockQuantity: inStock ? 15 : 0,
      mainImage: ProductImageRef(path: asset),
      galleryMedia: [
        ProductImageRef(path: asset),
        ProductImageRef(path: asset),
        ProductImageRef(path: asset),
        ProductImageRef(path: asset),
        if (category != ProductCategory.clothing) ProductImageRef(path: asset),
      ],
      experienceType: exp,
      vtoModelType: vtoModelType,
      availableColors: colors,
      defaultColor: colors.first,
      availableSizes: category == ProductCategory.clothing
          ? const {ProductSize.m, ProductSize.l}
          : const {},
      defaultSize: category == ProductCategory.clothing ? ProductSize.m : null,
      specifications: const [],
      deliveryEstimate: '3 - 5 Days',
      addedDate: addedDate,
      rating: rating,
      reviewCount: reviewCount,
      recommendationRank: recommendationRank,
      popularityScore: popularityScore,
      arMetadata: arMetadata,
    );
  }

  // 1. Explicit UI Products
  products.add(
    buildExplicit(
      id: 'luna-3-seater-sofa',
      title: 'Luna Right-Chaise Sectional Sofa',
      asset: AppAssets.bestSellerSofa,
      category: ProductCategory.furniture,
      exp: ProductExperienceType.roomAr,
      price: 20000,
      originalPrice: 25000,
      subcategory: 'Sofas',
      rating: 4.8,
      reviewCount: 124,
      description:
          'A right-hand chaise sectional in a warm-ivory woven linen, with low '
          'track arms and generously filled seat and back cushions. The '
          'extended chaise gives you room to stretch out — it comfortably '
          'seats four.',
      specs: const [
        ProductSpecification(
          label: 'Material',
          value: 'Warm-ivory woven linen',
        ),
        ProductSpecification(
          label: 'Dimensions',
          value: 'W 265 cm • D 165 cm • H 82 cm',
        ),
      ],
      arMetadata: kRoomArProductMetadata['luna-3-seater-sofa'],
      isBestSeller: true,
      isFeatured: true,
    ),
  );

  products.add(
    buildExplicit(
      id: 'boho-woven-rug',
      title: 'Boho Woven Rug',
      asset: AppAssets.bestSellerRug,
      category: ProductCategory.rugs,
      exp: ProductExperienceType.none,
      price: 8500,
      subcategory: 'Area Rugs',
      rating: 4.6,
      reviewCount: 89,
      specs: const [
        ProductSpecification(label: 'Material', value: 'Cotton/Jute Blend'),
        ProductSpecification(label: 'Dimensions', value: '150 cm x 200 cm'),
      ],
      isBestSeller: true,
      isPopularFurniture: true,
    ),
  );

  products.add(
    buildExplicit(
      id: 'classic-blue-shirt',
      title: 'Classic Blue Shirt',
      asset: AppAssets.bestSellerBlueShirt,
      category: ProductCategory.clothing,
      exp: ProductExperienceType.virtualTryOn,
      price: 4200,
      vtoModelType: ProductVtoModelType.male,
      subcategory: 'Shirts',
      rating: 5.0,
      reviewCount: 210,
      specs: const [
        ProductSpecification(label: 'Fabric', value: '100% Cotton'),
        ProductSpecification(label: 'Fit', value: 'Regular Fit'),
        ProductSpecification(label: 'Care', value: 'Machine wash cold'),
      ],
      isBestSeller: true,
      isRecentlyViewed: true,
    ),
  );

  products.add(
    buildExplicit(
      id: 'womens-blazer',
      title: 'Women\'s Blazer',
      asset: AppAssets.featuredWomensBlazer,
      category: ProductCategory.clothing,
      exp: ProductExperienceType.virtualTryOn,
      price: 12500,
      originalPrice: 15000,
      vtoModelType: ProductVtoModelType.female,
      subcategory: 'Blazers',
      rating: 4.7,
      reviewCount: 95,
      specs: const [
        ProductSpecification(label: 'Fabric', value: 'Wool Blend'),
        ProductSpecification(label: 'Fit', value: 'Tailored Fit'),
      ],
      isFeatured: true,
    ),
  );

  products.add(
    buildExplicit(
      id: 'modern-table-lamp',
      title: 'Modern Table Lamp',
      asset: AppAssets.newArrivalLampDecor,
      category: ProductCategory.lighting,
      exp: ProductExperienceType.roomAr,
      price: 5500,
      subcategory: 'Table Lamps',
      description:
          'A modern table lamp with a pierced ceramic base and a warm ivory '
          'linen drum shade, finished with a satin brass fitting.',
      specs: const [
        ProductSpecification(
          label: 'Material',
          value: 'Speckled ceramic, ivory linen shade, satin brass fitting',
        ),
        ProductSpecification(
          label: 'Dimensions',
          value: 'H 45 cm • W 20 cm • D 20 cm',
        ),
        ProductSpecification(label: 'Bulb Type', value: 'E27 LED'),
      ],
      arMetadata: kRoomArProductMetadata['modern-table-lamp'],
      isNewArrival: true,
    ),
  );

  products.add(
    buildExplicit(
      id: 'velvet-armchair',
      title: 'Velvet Armchair',
      asset: AppAssets.newArrivalArmchair,
      category: ProductCategory.furniture,
      exp: ProductExperienceType.roomAr,
      price: 18000,
      rating: 4.6,
      subcategory: 'Accent Chairs',
      arMetadata: kRoomArProductMetadata['velvet-armchair'],
      isNewArrival: true,
      isPopularFurniture: true,
      isRecentlyViewed: true,
    ),
  );

  products.add(
    buildExplicit(
      id: 'leather-jacket',
      title: 'Leather Jacket',
      asset: AppAssets.newArrivalJacket,
      category: ProductCategory.clothing,
      exp: ProductExperienceType.virtualTryOn,
      price: 15000,
      vtoModelType: ProductVtoModelType.male,
      subcategory: 'Jackets',
      specs: const [
        ProductSpecification(label: 'Fabric', value: 'Genuine Leather'),
        ProductSpecification(label: 'Fit', value: 'Slim Fit'),
      ],
      isNewArrival: true,
    ),
  );

  products.add(
    buildExplicit(
      id: 'ceramic-vases-set',
      title: 'Ceramic Vases Set',
      asset: AppAssets.newArrivalVases,
      category: ProductCategory.decor,
      exp: ProductExperienceType.none,
      price: 4500,
      rating: 4.5,
      subcategory: 'Vases',
      specs: const [
        ProductSpecification(label: 'Material', value: 'Ceramic'),
        ProductSpecification(
          label: 'Dimensions',
          value: 'Set of 3 (H 15-25cm)',
        ),
      ],
      isNewArrival: true,
      isPopularFurniture: true,
      isRecentlyViewed: true,
    ),
  );

  // `minimalist-bedroom-set` — permanently removed from the catalogue by
  // developer decision (Phase 9.2 closeout, 2026-09-09): deleted via Admin
  // (Firestore doc + app listing gone; its Storage objects were separately,
  // manually cleaned up). This is the canonical seed source that
  // `scripts/seed_products/products_seed.json` is exported from and a live
  // reseed writes from — an entry here would recreate the product in
  // Firestore on the next `dart run tool/export_product_seed.dart` +
  // `node seed_products.mjs --confirm`. Intentionally absent, not
  // model-blocked — see tracker §18/§33 and coverage matrix §3.2 for the
  // full history (it was never modelled: no `arMetadata` was ever attached
  // to this id, unlike `wooden-console` immediately below).

  products.add(
    buildExplicit(
      id: 'wooden-console',
      title: 'Wooden Console',
      asset: AppAssets.arEnabledConsole,
      category: ProductCategory.furniture,
      exp: ProductExperienceType.roomAr,
      price: 12000,
      subcategory: 'Console Tables',
      arMetadata: kRoomArProductMetadata['wooden-console'],
    ),
  );

  products.add(
    buildExplicit(
      id: 'glass-coffee-table',
      title: 'Round Wood Coffee Table',
      asset: AppAssets.arEnabledCoffeeTable,
      category: ProductCategory.furniture,
      exp: ProductExperienceType.roomAr,
      price: 16500,
      subcategory: 'Coffee Tables',
      description:
          'A round coffee table with a warm oak-finish top on a sculptural '
          'pedestal base — a grounded centrepiece for the living room.',
      specs: const [
        ProductSpecification(
          label: 'Material',
          value: 'Solid oak and oak veneer',
        ),
        ProductSpecification(label: 'Dimensions', value: 'Ø 90 cm • H 42 cm'),
      ],
      arMetadata: kRoomArProductMetadata['glass-coffee-table'],
    ),
  );

  products.add(
    buildExplicit(
      id: 'floral-summer-dress',
      title: 'Floral Summer Dress',
      asset: AppAssets.vtoWomensDress,
      category: ProductCategory.clothing,
      exp: ProductExperienceType.virtualTryOn,
      price: 6500,
      rating: 4.5,
      vtoModelType: ProductVtoModelType.female,
      subcategory: 'Dresses',
    ),
  );

  products.add(
    buildExplicit(
      id: 'casual-hoodie',
      title: 'Casual Hoodie',
      asset: AppAssets.vtoMensHoodie,
      category: ProductCategory.clothing,
      exp: ProductExperienceType.virtualTryOn,
      price: 4800,
      rating: 4.7,
      vtoModelType: ProductVtoModelType.male,
      subcategory: 'Hoodies',
    ),
  );

  products.add(
    buildExplicit(
      id: 'autumn-outfit',
      title: 'Autumn Outfit',
      asset: AppAssets.vtoWomensOutfit,
      category: ProductCategory.clothing,
      exp: ProductExperienceType.virtualTryOn,
      price: 14000,
      rating: 4.8,
      vtoModelType: ProductVtoModelType.female,
      subcategory: 'Outfits',
      isRecentlyViewed: true,
    ),
  );

  products.add(
    buildExplicit(
      id: 'marble-side-table',
      title: 'Marble Side Table',
      asset: AppAssets.popularSideTable,
      category: ProductCategory.furniture,
      exp: ProductExperienceType.roomAr,
      price: 9500,
      subcategory: 'Side Tables',
      arMetadata: kRoomArProductMetadata['marble-side-table'],
      isPopularFurniture: true,
    ),
  );

  // 2. Specific Explore Primary Items
  products.add(
    ProductModel(
      id: 'luna-accent-chair',
      sku: generateSku(ProductCategory.furniture),
      title: 'Luna Accent Chair',
      description:
          "The Luna Accent Chair brings a touch of mid-century modern elegance to your living space. With its sculptural silhouette, plush velvet upholstery, and tapered brass legs, it's designed for both comfort and statement-making style.",
      categoryId: 'furniture',
      categoryKind: ProductCategory.furniture,
      subcategory: 'Accent Chairs',
      priceAmount: 12000,
      originalPriceAmount: 16000,
      stockQuantity: 10,
      mainImage: ProductImageRef(path: AppAssets.pdLunaChairMain),
      galleryMedia: const [
        ProductImageRef(path: AppAssets.pdLunaChairMain),
        ProductImageRef(path: AppAssets.pdLunaChairView2),
        ProductImageRef(path: AppAssets.pdLunaChairView3),
        ProductImageRef(path: AppAssets.pdLunaChairView4),
        ProductImageRef(path: AppAssets.pdLunaChairView5),
      ],
      experienceType: ProductExperienceType.roomAr,
      availableColors: const {ProductColorOption.beige},
      defaultColor: ProductColorOption.beige,
      availableSizes: const {},
      specifications: const [
        ProductSpecification(
          label: 'Material',
          value: 'Premium Fabric, Solid Wood',
        ),
        ProductSpecification(
          label: 'Dimensions',
          value: 'W 70 cm • D 72 cm • H 82 cm',
        ),
      ],
      deliveryEstimate: '20 - 24 May, 2025',
      recommendationRank: 1,
      addedDate: DateTime.now(),
      popularityScore: 100,
      rating: 4.8,
      reviewCount: 124,
      arMetadata: kRoomArProductMetadata['luna-accent-chair'],
    ),
  );

  products.add(
    ProductModel(
      id: 'mens-oxford-shirt',
      sku: generateSku(ProductCategory.clothing),
      title: 'Men\'s Oxford Shirt',
      description:
          "A timeless Oxford shirt crafted for comfort and style. Perfect for work, weekend or everything in between.",
      categoryId: 'clothing',
      categoryKind: ProductCategory.clothing,
      subcategory: 'Shirts',
      priceAmount: 2200,
      originalPriceAmount: 3200,
      stockQuantity: 50,
      mainImage: ProductImageRef(path: AppAssets.pdOxfordShirtFront),
      galleryMedia: const [
        ProductImageRef(path: AppAssets.pdOxfordShirtFront),
        ProductImageRef(path: AppAssets.pdOxfordShirtBack),
        ProductImageRef(path: AppAssets.pdOxfordShirtFabric),
        ProductImageRef(path: AppAssets.pdOxfordShirtCollar),
      ],
      experienceType: ProductExperienceType.virtualTryOn,
      vtoModelType: ProductVtoModelType.male,
      availableColors: const {
        ProductColorOption.blue,
        ProductColorOption.gray,
        ProductColorOption.black,
        ProductColorOption.beige,
      },
      defaultColor: ProductColorOption.blue,
      availableSizes: const {
        ProductSize.s,
        ProductSize.m,
        ProductSize.l,
        ProductSize.xl,
        ProductSize.xxl,
      },
      defaultSize: ProductSize.m,
      specifications: const [
        ProductSpecification(
          label: 'Fabric',
          value: '100% Premium Cotton (Oxford Weave)',
        ),
        ProductSpecification(label: 'Fit', value: 'Regular Fit'),
        ProductSpecification(
          label: 'Care',
          value:
              'Machine wash cold with like colors.\nTumble dry low.\nWarm iron if needed.',
        ),
      ],
      deliveryEstimate: '2-4 Business Days',
      recommendationRank: 51,
      addedDate: DateTime.now(),
      popularityScore: 200,
      rating: 4.6,
      reviewCount: 128,
    ),
  );

  // 3. Dynamic Explore Items (Beige AR)
  for (int i = 2; i <= 24; i++) {
    final int price = 10000 + (i * 1000);
    final category = (i % 3 == 0)
        ? ProductCategory.decor
        : ((i % 2 == 0) ? ProductCategory.furniture : ProductCategory.rugs);

    String assetPath;
    String title;
    if (category == ProductCategory.furniture) {
      assetPath = AppAssets.featuredSofa;
      title = 'Beige AR Sofa $i';
    } else if (category == ProductCategory.decor) {
      assetPath = AppAssets.popularVase;
      title = 'Beige AR Vase $i';
    } else {
      assetPath = AppAssets.bestSellerRug;
      title = 'Beige AR Rug $i';
    }

    products.add(
      buildExploreItem(
        id: 'beige-ar-in-stock-$i',
        title: title,
        asset: assetPath,
        category: category,
        exp: ProductExperienceType.roomAr,
        price: price,
        inStock: true,
        colors: {ProductColorOption.beige},
        rating: 4.5,
        reviewCount: 120 + i,
        recommendationRank: i,
        addedDate: DateTime.now().subtract(Duration(days: i)),
        popularityScore: 100 - i,
        arMetadata: kRoomArProductMetadata['beige-ar-in-stock-$i'],
      ),
    );
  }

  // 4. Dynamic Explore Items (Other)
  for (int i = 2; i <= 12; i++) {
    final int price = 5000 + (i * 500);
    final category = (i % 2 == 0)
        ? ProductCategory.clothing
        : ProductCategory.lighting;
    final bool inStock = i % 2 == 0;
    final bool tryOn = category == ProductCategory.clothing && (i % 2 != 0);
    final bool ar = category != ProductCategory.clothing && (i % 3 == 0);

    final exp = tryOn
        ? ProductExperienceType.virtualTryOn
        : (ar ? ProductExperienceType.roomAr : ProductExperienceType.none);
    final color = (i % 2 == 0)
        ? ProductColorOption.black
        : ProductColorOption.blue;

    String assetPath;
    String title;
    if (category == ProductCategory.clothing) {
      assetPath = AppAssets.featuredWomensBlazer;
      title = 'Trendy Outfit $i';
    } else {
      assetPath = AppAssets.newArrivalLampDecor;
      title = 'Modern Lamp $i';
    }

    products.add(
      buildExploreItem(
        id: 'other-product-$i',
        title: title,
        asset: assetPath,
        category: category,
        exp: exp,
        vtoModelType: category == ProductCategory.clothing
            ? (i % 2 == 0
                  ? ProductVtoModelType.female
                  : ProductVtoModelType.male)
            : null,
        price: price,
        inStock: inStock,
        colors: {color},
        rating: 4.8,
        reviewCount: 200 + i,
        recommendationRank: 50 + i,
        addedDate: DateTime.now().subtract(Duration(days: 30 + i)),
        popularityScore: 200 - i,
      ),
    );
  }

  return products;
}
