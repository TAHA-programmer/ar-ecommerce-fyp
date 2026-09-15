import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../models/review_model.dart';
import 'review_star_row.dart';

/// A single published review card (Ratings/Reviews v1 Stage 6 read-only
/// display; Stage 8 adds the optional "Report" action). Shows the masked
/// author name ([ReviewModel.authorDisplayName] - a server-computed
/// snapshot stored directly on the review document, never a live profile
/// lookup; see that field's doc comment for why), star rating, optional
/// title, body, and the submission date - an "Edited" note when
/// [ReviewModel.hasBeenEdited].
///
/// [onReport] is `null` for the signed-in customer's OWN review (you can't
/// report yourself - `ProductReviewsSection` never passes a callback for
/// `viewModel.isMine(review)`) or when signed out; the "Report" action is
/// omitted entirely rather than rendered disabled, matching this app's
/// established "no dead button" convention.
class ReviewListItem extends StatelessWidget {
  final ReviewModel review;
  final VoidCallback? onReport;

  const ReviewListItem({super.key, required this.review, this.onReport});

  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: const BoxDecoration(
        border: Border(
          bottom: BorderSide(color: AppColors.neutralLight, width: 1),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ReviewStarRow(rating: review.rating.toDouble(), size: 14),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.authorDisplayName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                _dateFormat.format(review.createdAt),
                style: AppTypography.caption,
              ),
            ],
          ),
          if (review.hasBeenEdited) ...[
            const SizedBox(height: 2),
            Text('Edited', style: AppTypography.caption),
          ],
          if (review.title != null && review.title!.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              review.title!,
              style: AppTypography.label.copyWith(color: AppColors.textPrimary),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            review.body,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          if (onReport != null) ...[
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                style: TextButton.styleFrom(
                  padding: EdgeInsets.zero,
                  minimumSize: const Size(0, 32),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                onPressed: onReport,
                child: Text(
                  'Report',
                  style: AppTypography.caption.copyWith(
                    color: AppColors.textSecondary,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
