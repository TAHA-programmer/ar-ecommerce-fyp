import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../models/review_model.dart';
import '../viewmodels/reviews_viewmodel.dart';
import 'review_list_item.dart';
import 'review_rating_summary.dart';
import 'review_report_sheet.dart';
import 'review_sort_selector.dart';
import 'review_write_entry.dart';

/// The "Ratings & Reviews" section (Ratings/Reviews v1 Stage 6 read-only
/// list + Stage 7 write entry point) - rating summary + 1-5 star
/// distribution + sort control + paginated published-review list, with
/// every loading/empty/error state from v1 §0, plus the eligibility-gated
/// "Write a Review"/"Edit Your Review" entry ([ReviewWriteEntry]).
///
/// Inserted at the SAME point in both `ClothingProductDetailsLayout` and
/// `HomeProductDetailsLayout` (after `ExpandableProductDescription`, before
/// the category-specific spec/benefits section) - the third shared
/// cross-layout element after `ProductTitleBlock`/`ProductCategoryBreadcrumb`
/// (`24_RATINGS_REVIEWS_FEEDBACK_PLAN.md` §1).
///
/// Reads its [ReviewsViewModel] from `context` (a `ChangeNotifierProvider`
/// scoped alongside `ProductDetailsViewModel` in `ProductDetailsView`, keyed
/// by the same `productId`) rather than taking one as a constructor
/// parameter - this is the one section on the page backed by its own
/// independent ViewModel/data source, so threading it through both layouts'
/// existing `viewModel`-only constructors would misrepresent it as part of
/// `ProductDetailsViewModel`'s own state. [productTitle] IS threaded through
/// explicitly (both layouts already have it in scope) - purely display
/// context for the Write Review screen, not something worth a cross-feature
/// dependency on `ProductDetailsViewModel` to avoid re-fetching.
///
/// The list itself stays READ-ONLY for edit/delete (that's the signed-in
/// customer's OWN review, via `ReviewWriteEntry`/"My Reviews" - Stage 7) -
/// Stage 8 adds the one other per-review action every OTHER review gets:
/// "Report" (omitted on the customer's own review, see
/// `ReviewListItem.onReport`'s doc comment). The existing STATIC
/// `rating`/`reviewCount` shown in `ProductTitleBlock` is untouched (v1 §0
/// decision 16 - only the final migration stage cuts over to live
/// aggregates).
class ProductReviewsSection extends StatelessWidget {
  final String productTitle;

  const ProductReviewsSection({super.key, required this.productTitle});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ReviewsViewModel>();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Ratings & Reviews', style: AppTypography.title),
          const SizedBox(height: 16),
          ReviewWriteEntry(productTitle: productTitle),
          _ReviewsSectionBody(viewModel: viewModel),
        ],
      ),
    );
  }
}

class _ReviewsSectionBody extends StatelessWidget {
  final ReviewsViewModel viewModel;

  const _ReviewsSectionBody({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    if (viewModel.hasLoadError) {
      return _ReviewsErrorState(onRetry: () => viewModel.refresh());
    }

    if (viewModel.isEmpty) {
      return const _ReviewsEmptyState();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReviewRatingSummary(stats: viewModel.stats),
        const SizedBox(height: 20),
        ReviewSortSelector(
          selected: viewModel.sort,
          onChanged: (option) => viewModel.changeSort(option),
        ),
        const SizedBox(height: 4),
        for (final review in viewModel.reviews)
          ReviewListItem(
            key: ValueKey(review.id),
            review: review,
            onReport: viewModel.isMine(review)
                ? null
                : () => _reportReview(context, viewModel, review),
          ),
        if (viewModel.hasMore) _LoadMoreControl(viewModel: viewModel),
      ],
    );
  }

  Future<void> _reportReview(
    BuildContext context,
    ReviewsViewModel viewModel,
    ReviewModel review,
  ) async {
    final submission = await showReviewReportSheet(context);
    if (submission == null || !context.mounted) return;

    final error = await viewModel.reportReview(
      reviewId: review.id,
      reason: submission.reason,
      note: submission.note,
    );
    if (!context.mounted) return;
    if (error != null) {
      AppToast.error(context, error);
    } else {
      AppToast.success(context, "Thanks - we'll take a look.");
    }
  }
}

class _LoadMoreControl extends StatelessWidget {
  final ReviewsViewModel viewModel;

  const _LoadMoreControl({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: viewModel.isLoadingMore
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.primary,
                ),
              )
            : TextButton(
                onPressed: () => viewModel.loadMore(),
                child: Text(
                  'Load more reviews',
                  style: AppTypography.label.copyWith(color: AppColors.primary),
                ),
              ),
      ),
    );
  }
}

class _ReviewsEmptyState extends StatelessWidget {
  const _ReviewsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No reviews yet',
            style: AppTypography.label.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: 4),
          Text(
            'Be the first to share your thoughts once your order has been '
            'delivered.',
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
      ),
    );
  }
}

class _ReviewsErrorState extends StatelessWidget {
  final VoidCallback onRetry;

  const _ReviewsErrorState({required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Couldn't load reviews.",
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton(
              style: TextButton.styleFrom(padding: EdgeInsets.zero),
              onPressed: onRetry,
              child: Text(
                'Retry',
                style: AppTypography.label.copyWith(color: AppColors.primary),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
