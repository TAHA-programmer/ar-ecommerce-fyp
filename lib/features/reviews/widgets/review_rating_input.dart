import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

/// Five tappable stars for picking a 1-5 review rating (Ratings/Reviews v1
/// Stage 7) - the interactive counterpart to the read-only [ReviewStarRow]
/// used elsewhere in this feature. [rating] of `0` means "nothing picked
/// yet" (every star outlined) - the write screen uses this to keep its
/// submit button disabled until a real 1-5 choice is made, never defaulting
/// to a silently-pre-selected star.
class ReviewRatingInput extends StatelessWidget {
  final int rating;
  final ValueChanged<int> onChanged;
  final double size;

  const ReviewRatingInput({
    super.key,
    required this.rating,
    required this.onChanged,
    this.size = 40,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (index) {
        final starValue = index + 1;
        final filled = starValue <= rating;
        return IconButton(
          onPressed: () => onChanged(starValue),
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(),
          visualDensity: VisualDensity.compact,
          icon: Icon(
            filled ? Icons.star_rounded : Icons.star_outline_rounded,
            size: size,
            color: filled ? AppColors.primary : AppColors.neutralMediumLight,
          ),
        );
      }),
    );
  }
}
