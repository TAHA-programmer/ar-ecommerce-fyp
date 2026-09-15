import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../../../../core/widgets/states/app_empty_state.dart';
import '../../../reviews/models/review_moderation_action.dart';
import '../../views/admin_shell.dart';
import '../viewmodels/admin_reviews_viewmodel.dart';
import '../widgets/admin_review_card.dart';
import '../widgets/admin_review_moderation_sheet.dart';
import '../widgets/admin_reviews_filter_bar.dart';

/// The Admin "Reviews" screen (Ratings/Reviews v1 Stage 8) - every review
/// across every product, filterable by status/flagged (flagged always
/// surfaced first within the active filter), each with its moderation
/// action row and an expandable report audit trail. Reached from the Admin
/// account sheet (`AdminAccountSheet`) rather than a bottom-nav tab -
/// matches `AdminArMediaManagementView`'s own precedent for a standalone
/// admin surface that isn't one of the four primary tabs.
class AdminReviewsView extends StatelessWidget {
  const AdminReviewsView({super.key});

  @override
  Widget build(BuildContext context) {
    final viewModel = context.watch<AdminReviewsViewModel>();

    return AdminShell(
      currentIndex: 3,
      title: 'Reviews',
      showGreeting: false,
      onBack: () => Navigator.of(context).pop(),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.m,
              AppSpacing.s,
              AppSpacing.m,
              AppSpacing.s,
            ),
            child: AdminReviewsFilterBar(
              selected: viewModel.filter,
              flaggedCount: viewModel.flaggedCount,
              onChanged: viewModel.setFilter,
            ),
          ),
          Expanded(child: _Body(viewModel: viewModel)),
        ],
      ),
    );
  }
}

class _Body extends StatelessWidget {
  final AdminReviewsViewModel viewModel;

  const _Body({required this.viewModel});

  @override
  Widget build(BuildContext context) {
    if (viewModel.isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: AppColors.primary),
      );
    }

    if (viewModel.hasLoadError) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                "Couldn't load reviews.",
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              TextButton(
                onPressed: () => viewModel.refresh(),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    final reviews = viewModel.filteredReviews;

    if (reviews.isEmpty) {
      return RefreshIndicator(
        onRefresh: viewModel.refresh,
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
          children: const [
            AppEmptyState(
              title: 'No reviews here',
              message: 'Nothing matches this filter right now.',
              icon: Icons.rate_review_outlined,
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: viewModel.refresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.m,
          0,
          AppSpacing.m,
          AppSpacing.xl,
        ),
        itemCount: reviews.length,
        itemBuilder: (context, index) {
          final review = reviews[index];
          return AdminReviewCard(
            review: review,
            productSummary: viewModel.productSummaryFor(review.productId),
            isModerating: viewModel.isModerating(review.id),
            reports: viewModel.reportsFor(review.id),
            isLoadingReports: viewModel.isLoadingReports(review.id),
            onLoadReports: () => viewModel.loadReportsFor(review.id),
            onModerate: (action) => _moderate(context, review.id, action),
          );
        },
      ),
    );
  }

  Future<void> _moderate(
    BuildContext context,
    String reviewId,
    ReviewModerationAction action,
  ) async {
    final reason = await showAdminReviewModerationSheet(
      context,
      action: action,
    );
    if (reason == null || !context.mounted) return;

    final error = await viewModel.moderate(
      reviewId: reviewId,
      action: action,
      reason: reason,
    );
    if (!context.mounted) return;
    if (error != null) {
      AppToast.error(context, error);
    } else {
      AppToast.success(context, 'Review updated.');
    }
  }
}
