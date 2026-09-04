import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/models/product/product_image_ref.dart';
import '../../../core/models/product/product_experience_type.dart';
import '../../../core/widgets/product_image_view.dart';

class FurnitureProductGallery extends StatelessWidget {
  final List<ProductImageRef> gallery;
  final int activeIndex;
  final ValueChanged<int> onThumbnailTap;
  final ProductExperienceType experienceType;

  const FurnitureProductGallery({
    super.key,
    required this.gallery,
    required this.activeIndex,
    required this.onThumbnailTap,
    this.experienceType = ProductExperienceType.none,
  });

  @override
  Widget build(BuildContext context) {
    if (gallery.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24.0),
          child: AspectRatio(
            aspectRatio: 1.0, // Square ratio as a good default for furniture
            child: Stack(
              children: [
                Container(
                  width: double.infinity,
                  height: double.infinity,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    color: AppColors.surface, // Clean white background
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: ProductImageView(
                    imageRef: gallery[activeIndex],
                    fit: BoxFit.cover,
                  ),
                ),
                if (experienceType == ProductExperienceType.roomAr)
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
                            Icons.view_in_ar_rounded,
                            color: AppColors.primary,
                            size: 16,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'AR',
                            style: AppTypography.label.copyWith(
                              color: AppColors.primary,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.9),
                      borderRadius: BorderRadius.circular(20),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.1),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Text(
                      '${activeIndex + 1} / ${gallery.length}',
                      style: AppTypography.label.copyWith(
                        fontWeight: FontWeight.w600,
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 64,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 24),
            itemCount: gallery.length,
            itemBuilder: (context, index) {
              final isSelected = index == activeIndex;
              return GestureDetector(
                onTap: () => onThumbnailTap(index),
                child: Container(
                  width: 64,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border.all(
                      color: isSelected
                          ? AppColors.primary
                          : Colors.transparent,
                      width: isSelected ? 2 : 0,
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Container(
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: AppColors.neutralMediumLight,
                        width: 1,
                      ),
                      borderRadius: BorderRadius.circular(10), // inner
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
    );
  }
}
