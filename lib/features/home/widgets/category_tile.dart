import 'package:flutter/material.dart';
import '../../../../app/routes/route_names.dart';
import '../../../../app/routes/explore_launch_intent.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/models/product/product_category.dart';
import '../../../core/theme/app_colors.dart';
import '../models/category_model.dart';

/// Themed bundled fallback image per AR/VTO kind, used when a category
/// (typically a newly Admin-created one) has no photo of its own yet -
/// every real category has exactly one of these five kinds, so this always
/// has a match. Keeps a photo-less category looking like a proper card
/// instead of a bare placeholder icon, matching the established four.
String _fallbackAssetFor(ProductCategory kind) {
  switch (kind) {
    case ProductCategory.furniture:
      return AppAssets.categoryFurniture;
    case ProductCategory.clothing:
      return AppAssets.categoryClothing;
    case ProductCategory.rugs:
      return AppAssets.categoryRugs;
    case ProductCategory.decor:
      return AppAssets.categoryDecor;
    case ProductCategory.lighting:
      return AppAssets.newArrivalLampDecor;
    case ProductCategory.all:
      return AppAssets.categoryFurniture;
  }
}

class CategoryTile extends StatelessWidget {
  final CategoryModel category;

  const CategoryTile({super.key, required this.category});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () {
        // Exact-category navigation (Phase 8.8b) - shows only this specific
        // category's products, not every product sharing its broad AR/VTO
        // kind. See ExploreFilterState's categoryId/category split.
        Navigator.pushNamed(
          context,
          RouteNames.explore,
          arguments: ExploreLaunchIntent(categoryId: category.id),
        );
      },
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 6),
        width: 88,
        height: 88,
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: Colors.black.withValues(alpha: 0.05),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 6,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        // Inset "inner card" frame around the photo itself - independent
        // of whatever image is used, so every tile (the original four,
        // Lighting, and any category an Admin adds later) shows the same
        // outer-card-border + inner-image-border look, rather than relying
        // on individual bundled photos happening to already have their own
        // baked-in white matting/padding.
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.black.withValues(alpha: 0.08),
                width: 1,
              ),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(13),
              child: _buildImage(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildImage() {
    if (category.imageUrl.isNotEmpty) {
      return Image.network(
        category.imageUrl,
        fit: BoxFit.cover,
        loadingBuilder: (context, child, progress) {
          if (progress == null) return child;
          return const ColoredBox(
            color: AppColors.neutralLight,
            child: Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          );
        },
        errorBuilder: (context, error, stackTrace) =>
            Image.asset(_fallbackAssetFor(category.kind), fit: BoxFit.cover),
      );
    }
    if (category.imageAssetPath.isNotEmpty) {
      return Image.asset(category.imageAssetPath, fit: BoxFit.cover);
    }
    // No photo uploaded yet (typically a brand-new Admin-created category) -
    // a themed bundled image keeps this card looking like a proper photo
    // tile instead of a bare placeholder icon.
    return Image.asset(_fallbackAssetFor(category.kind), fit: BoxFit.cover);
  }
}
