import '../constants/app_assets.dart';
import '../models/product/product_category.dart';

/// One of the five canonical seeded categories, BEFORE its image has been
/// uploaded to Storage. [sourceImageAssetPath] is a bundled asset path -
/// used ONLY by the developer-only seed tooling
/// (`tool/export_category_seed.dart` -> `scripts/seed_categories/`) as the
/// local file to upload; it is never written to Firestore and never reaches
/// the app as a `CommerceCategoryModel.imageUrl` value (which is always
/// either `''` or a real Storage download URL - see that model's doc
/// comment). This is the one narrow, deliberate exception to "products
/// only reference asset paths pre-migration" - these five bundled images
/// exist specifically to be uploaded once by the seed script, never
/// rendered directly by the app as `source: asset`.
class CategorySeedEntry {
  final String key;
  final String name;
  final ProductCategory kind;
  final int sortOrder;
  final String sourceImageAssetPath;

  const CategorySeedEntry({
    required this.key,
    required this.name,
    required this.kind,
    required this.sortOrder,
    required this.sourceImageAssetPath,
  });
}

/// The single Dart source of truth for the five canonical seeded
/// categories - mirrors `buildMockProductSeedData()`'s role for products.
/// `tool/export_category_seed.dart` exports this to JSON;
/// `scripts/seed_categories/seed_categories.mjs` uploads each entry's image
/// and writes the real category document. `MockCategoryRepository`'s
/// `defaultMockCategories()` mirrors the same five key/name/kind/sortOrder
/// values (with an empty `imageUrl`, since a mock has no Storage to upload
/// to) so tests and the real seed never silently drift apart on identity.
List<CategorySeedEntry> buildCategorySeedData() => const [
  CategorySeedEntry(
    key: 'furniture',
    name: 'Furniture',
    kind: ProductCategory.furniture,
    sortOrder: 10,
    sourceImageAssetPath: AppAssets.categoryFurniture,
  ),
  CategorySeedEntry(
    key: 'clothing',
    name: 'Clothing',
    kind: ProductCategory.clothing,
    sortOrder: 20,
    sourceImageAssetPath: AppAssets.categoryClothing,
  ),
  CategorySeedEntry(
    key: 'rugs',
    name: 'Rugs',
    kind: ProductCategory.rugs,
    sortOrder: 30,
    sourceImageAssetPath: AppAssets.categoryRugs,
  ),
  CategorySeedEntry(
    key: 'decor',
    name: 'Decor',
    kind: ProductCategory.decor,
    sortOrder: 40,
    sourceImageAssetPath: AppAssets.categoryDecor,
  ),
  CategorySeedEntry(
    key: 'lighting',
    name: 'Lighting',
    kind: ProductCategory.lighting,
    sortOrder: 50,
    sourceImageAssetPath: AppAssets.newArrivalLampDecor,
  ),
];
