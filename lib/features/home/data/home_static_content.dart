import '../../../core/constants/app_assets.dart';
import '../models/category_model.dart';
import '../models/home_banner_model.dart';

/// Static promotional content shared by every [HomeRepository]
/// implementation. Banners/categories are not product data - Phase 8.5
/// migrates product reads only; dynamic Firestore-backed categories are
/// Phase 8.8. Kept in one place so Mock and Firestore implementations can
/// never drift apart.
const List<HomeBannerModel> homeStaticBanners = [
  HomeBannerModel(
    id: 'b1',
    imageAssetPath: AppAssets.homeHeroArRoom,
    title1: 'See It.',
    title2: 'Love It.',
    title3: 'Place It.',
    body: 'Use AR to visualize products\nin your space before you\nbuy.',
    ctaText: 'Explore AR',
  ),
  HomeBannerModel(
    id: 'b2',
    imageAssetPath: AppAssets.homeHeroVirtualTryon,
    title1: 'Try It.',
    title2: 'Style It.',
    title3: 'Love It.',
    body: 'See how clothing looks on you\nbefore you buy.',
    ctaText: 'Try It On',
  ),
  HomeBannerModel(
    id: 'b3',
    imageAssetPath: AppAssets.homeHeroNewArrivals,
    title1: 'Fresh',
    title2: 'Finds.',
    title3: 'Made for You.',
    body: 'Discover fresh furniture,\ndecor & fashion picked for you.',
    ctaText: 'Shop New',
  ),
];

const List<CategoryModel> homeStaticCategories = [
  CategoryModel(
    id: 'c1',
    name: 'Furniture',
    imageAssetPath: AppAssets.categoryFurniture,
  ),
  CategoryModel(
    id: 'c2',
    name: 'Decor',
    imageAssetPath: AppAssets.categoryDecor,
  ),
  CategoryModel(id: 'c3', name: 'Rugs', imageAssetPath: AppAssets.categoryRugs),
  CategoryModel(
    id: 'c4',
    name: 'Clothing',
    imageAssetPath: AppAssets.categoryClothing,
  ),
  CategoryModel(
    id: 'c5',
    name: 'Wall Decor',
    imageAssetPath: AppAssets.categoryWallDecor,
  ),
];
