import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Five discrete stars, filled up to `rating.round()` - the same
/// filled/outlined star vocabulary as `RatingRow`/`ProductTitleBlock`
/// elsewhere in Product Details, just applied per-star rather than as a
/// single icon + number. A whole-star simplification (no partial/fractional
/// fill) - honest for a 1-5 integer review rating and for a rounded
/// aggregate average alike.
class ReviewStarRow extends StatelessWidget {
  final double rating;
  final double size;
  final Color filledColor;
  final Color emptyColor;

  const ReviewStarRow({
    super.key,
    required this.rating,
    this.size = 16,
    this.filledColor = AppColors.primary,
    this.emptyColor = AppColors.neutralMediumLight,
  });

  @override
  Widget build(BuildContext context) {
    final filledCount = rating.round().clamp(0, 5);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final filled = index < filledCount;
        return Padding(
          padding: EdgeInsets.only(right: index < 4 ? 2.0 : 0),
          child: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: filled ? filledColor : emptyColor,
          ),
        );
      }),
    );
  }
}
