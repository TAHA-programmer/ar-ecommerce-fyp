import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../../core/models/product/product_summary_model.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/product_image_view.dart';
import '../models/review_model.dart';
import '../models/review_status.dart';
import 'review_star_row.dart';

/// One card on the Profile "My Reviews" list (Ratings/Reviews v1 Stage 7) -
/// the resolved product (title + thumbnail, or an honest generic fallback
/// if resolution failed/the product is gone), the review itself, and
/// Edit/Delete actions. Shows a small status note whenever [review.status]
/// is not [ReviewStatus.published] - the customer's own review is always
/// readable to them regardless of moderation state (`firestore.rules`), so
/// this card must never silently hide that fact.
class MyReviewCard extends StatelessWidget {
  final ReviewModel review;
  final ProductSummaryModel? productSummary;
  final bool isDeleting;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  const MyReviewCard({
    super.key,
    required this.review,
    required this.productSummary,
    required this.isDeleting,
    required this.onEdit,
    required this.onDelete,
  });

  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    final summary = productSummary;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.neutralMediumLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: summary != null
                    ? ProductImageView(
                        imageRef: summary.image,
                        width: 48,
                        height: 48,
                        fit: BoxFit.cover,
                      )
                    : Container(
                        width: 48,
                        height: 48,
                        color: AppColors.neutralLight,
                        child: const Icon(
                          Icons.inventory_2_outlined,
                          color: AppColors.textSecondary,
                          size: 20,
                        ),
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      summary?.title ?? 'Product',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.label.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        ReviewStarRow(
                          rating: review.rating.toDouble(),
                          size: 14,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _dateFormat.format(review.createdAt),
                          style: AppTypography.caption,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.status != ReviewStatus.published) ...[
            const SizedBox(height: 8),
            Text(
              review.status == ReviewStatus.hidden
                  ? 'Hidden - not currently visible to other customers.'
                  : 'Rejected - not visible to other customers.',
              style: AppTypography.caption.copyWith(color: AppColors.error),
            ),
          ],
          if (review.title != null && review.title!.isNotEmpty) ...[
            const SizedBox(height: 10),
            Text(
              review.title!,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
          const SizedBox(height: 6),
          Text(
            review.body,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(
                onPressed: isDeleting ? null : onEdit,
                icon: const Icon(
                  Icons.edit_outlined,
                  size: 16,
                  color: AppColors.primary,
                ),
                label: Text(
                  'Edit',
                  style: AppTypography.label.copyWith(color: AppColors.primary),
                ),
              ),
              const SizedBox(width: 8),
              TextButton.icon(
                onPressed: isDeleting ? null : onDelete,
                icon: isDeleting
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.error,
                        ),
                      )
                    : const Icon(
                        Icons.delete_outline,
                        size: 16,
                        color: AppColors.error,
                      ),
                label: isDeleting
                    ? const SizedBox.shrink()
                    : Text(
                        'Delete',
                        style: AppTypography.label.copyWith(
                          color: AppColors.error,
                        ),
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
