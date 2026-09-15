import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../app/routes/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../models/write_review_args.dart';
import '../viewmodels/reviews_viewmodel.dart';

/// The eligibility-gated "Write a Review" / "Edit Your Review" entry point
/// on Product Details (Ratings/Reviews v1 Stage 7, tracker §7). Renders
/// NOTHING while [ReviewsViewModel.isLoading] (own-state not resolved yet)
/// or once resolved when [ReviewsViewModel.isEligibleToReview] is `false` -
/// never a dead/disabled button promising something the customer can't
/// actually do (the same "no dead button" principle already established
/// for Room AR / Virtual Try-On entry points elsewhere in this app). The
/// REAL gate is still `submitReview`'s own server-side re-verification;
/// this is display-only, matching `ReviewsViewModel.isEligibleToReview`'s
/// own contract.
class ReviewWriteEntry extends StatelessWidget {
  final String productTitle;

  const ReviewWriteEntry({super.key, required this.productTitle});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<ReviewsViewModel>();

    if (viewModel.isLoading || !viewModel.isEligibleToReview) {
      return const SizedBox.shrink();
    }

    final isEditing = viewModel.myReview != null;

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: SizedBox(
        width: double.infinity,
        child: OutlinedButton.icon(
          onPressed: () async {
            final result = await Navigator.pushNamed(
              context,
              RouteNames.writeReview,
              arguments: WriteReviewArgs(
                productId: viewModel.productId,
                productTitle: productTitle,
              ),
            );
            if (result == true && context.mounted) {
              context.read<ReviewsViewModel>().refresh();
            }
          },
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary, width: 1.5),
            padding: const EdgeInsets.symmetric(vertical: 12),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
          icon: Icon(
            isEditing ? Icons.edit_outlined : Icons.rate_review_outlined,
            size: 18,
          ),
          label: Text(
            isEditing ? 'Edit Your Review' : 'Write a Review',
            style: AppTypography.label.copyWith(color: AppColors.primary),
          ),
        ),
      ),
    );
  }
}
