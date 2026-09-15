import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../models/product_rating_stats.dart';
import 'review_star_row.dart';

/// The average-rating + star + 1-5 distribution block at the top of the
/// reviews section (Ratings/Reviews v1 Stage 6). Purely a function of
/// [stats] - no loading/error state of its own (the parent
/// `ProductReviewsSection` owns those).
class ReviewRatingSummary extends StatelessWidget {
  final ProductRatingStats stats;

  const ReviewRatingSummary({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(
          width: 96,
          child: Column(
            children: [
              Text(
                stats.averageRating.toStringAsFixed(1),
                style: AppTypography.headingMedium,
              ),
              const SizedBox(height: 4),
              ReviewStarRow(rating: stats.averageRating, size: 16),
              const SizedBox(height: 4),
              Text(
                stats.ratingCount == 1
                    ? '1 review'
                    : '${stats.ratingCount} reviews',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            children: [
              for (var stars = 5; stars >= 1; stars--)
                _DistributionBarRow(
                  stars: stars,
                  fraction: stats.fractionForStars(stars),
                  count: stats.countForStars(stars),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _DistributionBarRow extends StatelessWidget {
  final int stars;
  final double fraction;
  final int count;

  const _DistributionBarRow({
    required this.stars,
    required this.fraction,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        children: [
          SizedBox(
            width: 12,
            child: Text(
              '$stars',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          const SizedBox(width: 4),
          const Icon(
            Icons.star_rounded,
            size: 10,
            color: AppColors.neutralDark,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: Stack(
                children: [
                  Container(height: 6, color: AppColors.neutralLight),
                  FractionallySizedBox(
                    widthFactor: fraction.clamp(0.0, 1.0),
                    child: Container(height: 6, color: AppColors.primary),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 24,
            child: Text(
              '$count',
              textAlign: TextAlign.right,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
