import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/routes/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../models/review_model.dart';
import '../models/write_review_args.dart';
import '../viewmodels/my_reviews_viewmodel.dart';
import '../widgets/my_review_card.dart';

/// The Profile "My Reviews" screen (Ratings/Reviews v1 Stage 7) - every
/// review the signed-in customer has written, across every product, with
/// Edit (confirm -> [RouteNames.writeReview]) and Delete (confirm) actions -
/// both gated behind their own confirmation dialog before anything happens.
class MyReviewsView extends StatelessWidget {
  const MyReviewsView({super.key});

  Future<void> _confirmDelete(
    BuildContext context,
    MyReviewsViewModel viewModel,
    ReviewModel review,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mediumBorder,
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        title: Text('Delete Review?', style: AppTypography.title),
        content: Text(
          'This permanently deletes your review. This cannot be undone.',
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.error,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final error = await viewModel.deleteReview(review);
    if (!context.mounted) return;
    if (error != null) {
      AppToast.error(context, error);
    } else {
      AppToast.success(context, 'Review deleted.');
    }
  }

  Future<void> _edit(
    BuildContext context,
    MyReviewsViewModel viewModel,
    ReviewModel review,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.mediumBorder,
          side: const BorderSide(color: AppColors.primary, width: 2),
        ),
        title: Text('Edit Review?', style: AppTypography.title),
        content: Text(
          "You're about to edit this review. Continue?",
          style: AppTypography.bodyMedium,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(
              'Cancel',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.primaryDark,
              ),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: AppColors.white,
            ),
            child: const Text('Edit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final result = await Navigator.pushNamed(
      context,
      RouteNames.writeReview,
      arguments: WriteReviewArgs(
        productId: review.productId,
        productTitle:
            viewModel.productSummaryFor(review.productId)?.title ?? 'Product',
      ),
    );
    if (result == true && context.mounted) {
      viewModel.refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<MyReviewsViewModel>();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.background,
        elevation: 0,
        iconTheme: const IconThemeData(color: AppColors.textPrimary),
        title: Text('My Reviews', style: AppTypography.title),
      ),
      body: SafeArea(child: _buildBody(context, viewModel)),
    );
  }

  Widget _buildBody(BuildContext context, MyReviewsViewModel viewModel) {
    if (viewModel.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (viewModel.hasLoadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Couldn't load your reviews.",
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: () => viewModel.refresh(),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: AppColors.white,
                ),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (viewModel.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.rate_review_outlined,
                size: 48,
                color: AppColors.neutralMedium,
              ),
              const SizedBox(height: 16),
              Text(
                "You haven't written any reviews yet",
                style: AppTypography.label.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Reviews you write for delivered orders will show up here.',
                textAlign: TextAlign.center,
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      color: AppColors.primary,
      child: ListView.builder(
        padding: const EdgeInsets.all(24),
        itemCount: viewModel.reviews.length,
        itemBuilder: (context, index) {
          final review = viewModel.reviews[index];
          return MyReviewCard(
            key: ValueKey(review.id),
            review: review,
            productSummary: viewModel.productSummaryFor(review.productId),
            isDeleting: viewModel.isDeleting(review.id),
            onEdit: () => _edit(context, viewModel, review),
            onDelete: () => _confirmDelete(context, viewModel, review),
          );
        },
      ),
    );
  }
}
