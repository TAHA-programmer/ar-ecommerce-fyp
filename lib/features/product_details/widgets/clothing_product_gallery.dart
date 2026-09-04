import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/models/product/product_image_ref.dart';
import '../../../core/models/product/product_experience_type.dart';
import '../../../core/widgets/product_image_view.dart';

class ClothingProductGallery extends StatelessWidget {
  final List<ProductImageRef> gallery;
  final int activeIndex;
  final ValueChanged<int> onThumbnailTap;
  final ProductExperienceType experienceType;

  const ClothingProductGallery({
    super.key,
    required this.gallery,
    required this.activeIndex,
    required this.onThumbnailTap,
    this.experienceType = ProductExperienceType.none,
  });

  @override
  Widget build(BuildContext context) {
    if (gallery.isEmpty) return const SizedBox.shrink();

    // Use AspectRatio to determine layout instead of hardcoded screen percentage
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: AspectRatio(
        aspectRatio: 0.85, // Adjust based on Figma frame
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Main Image (Left)
            Expanded(
              child: Stack(
                children: [
                  Container(
                    width: double.infinity,
                    height: double.infinity,
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(16),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: ProductImageView(
                      imageRef: gallery[activeIndex],
                      fit: BoxFit.cover,
                    ),
                  ),
                  // Pagination dots at bottom center
                  Positioned(
                    bottom: 16,
                    left: 0,
                    right: 0,
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(gallery.length, (index) {
                        final isSelected = index == activeIndex;
                        return Container(
                          width: isSelected ? 8 : 6,
                          height: isSelected ? 8 : 6,
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? AppColors.primary
                                : Colors.white.withValues(alpha: 0.5),
                            shape: BoxShape.circle,
                          ),
                        );
                      }),
                    ),
                  ),
                  // TRY-ON badge bottom left
                  if (experienceType == ProductExperienceType.virtualTryOn)
                    Positioned(
                      top: 16,
                      left: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.05),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.accessibility_new_rounded,
                              color: AppColors.primary,
                              size: 16,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              'TRY-ON',
                              style: AppTypography.label.copyWith(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            // Thumbnail Rail (Right)
            SizedBox(
              width: 64,
              child: ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: gallery.length,
                itemBuilder: (context, index) {
                  final isActive = index == activeIndex;
                  return GestureDetector(
                    onTap: () => onThumbnailTap(index),
                    child: Container(
                      height: 80,
                      margin: const EdgeInsets.only(bottom: 12),
                      decoration: BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isActive
                              ? AppColors.primary
                              : Colors.transparent,
                          width: isActive ? 2 : 0,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Container(
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(10), // inner
                          border: Border.all(
                            color: AppColors.neutralMediumLight,
                            width: 1,
                          ),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: ProductImageView(
                          imageRef: gallery[index],
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
