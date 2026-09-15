import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../../core/models/product/product_summary_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../reviews/models/review_model.dart';
import '../../../reviews/models/review_moderation_action.dart';
import '../../../reviews/models/review_report_model.dart';
import '../../../reviews/models/review_report_reason.dart';
import '../../../reviews/models/review_status.dart';
import '../../../reviews/widgets/review_star_row.dart';

/// One review in the Admin Reviews list (Ratings/Reviews v1 Stage 8) -
/// product/author/rating/body, a status badge, a flagged-for-review badge
/// with its report count, the moderation audit note (reason/who/when) when
/// present, an expandable "View reports" audit trail, and the
/// hide/restore/reject action row (only the two actions that would change
/// the review's CURRENT status are shown - a same-status action would be a
/// pointless re-stamp).
class AdminReviewCard extends StatefulWidget {
  final ReviewModel review;
  final ProductSummaryModel? productSummary;
  final bool isModerating;
  final List<ReviewReportModel>? reports;
  final bool isLoadingReports;
  final VoidCallback onLoadReports;
  final ValueChanged<ReviewModerationAction> onModerate;

  const AdminReviewCard({
    super.key,
    required this.review,
    required this.productSummary,
    required this.isModerating,
    required this.reports,
    required this.isLoadingReports,
    required this.onLoadReports,
    required this.onModerate,
  });

  @override
  State<AdminReviewCard> createState() => _AdminReviewCardState();
}

class _AdminReviewCardState extends State<AdminReviewCard> {
  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  bool _reportsExpanded = false;

  @override
  Widget build(BuildContext context) {
    final review = widget.review;
    return Container(
      key: Key('admin_review_card_${review.id}'),
      margin: const EdgeInsets.only(bottom: AppSpacing.m),
      padding: const EdgeInsets.all(AppSpacing.m),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: AppRadii.mediumBorder,
        border: Border.all(color: AppColors.neutralLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.productSummary?.title ?? review.productId,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              _StatusBadge(status: review.status),
            ],
          ),
          if (review.flaggedForReview) ...[
            const SizedBox(height: 4),
            _FlaggedBadge(reportCount: review.reportCount),
          ],
          const SizedBox(height: AppSpacing.s),
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
          if (review.moderationReason != null) ...[
            const SizedBox(height: AppSpacing.s),
            Container(
              padding: const EdgeInsets.all(AppSpacing.s),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: AppRadii.smallBorder,
              ),
              child: Text(
                'Moderation note: ${review.moderationReason}'
                '${review.moderatedAt != null ? ' - ${_dateFormat.format(review.moderatedAt!)}' : ''}',
                style: AppTypography.caption,
              ),
            ),
          ],
          if (review.reportCount > 0) ...[
            const SizedBox(height: AppSpacing.xs),
            TextButton(
              key: Key('admin_review_view_reports_button_${review.id}'),
              style: TextButton.styleFrom(
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, 32),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              onPressed: () {
                setState(() => _reportsExpanded = !_reportsExpanded);
                if (_reportsExpanded) widget.onLoadReports();
              },
              child: Text(
                _reportsExpanded
                    ? 'Hide reports'
                    : 'View reports (${review.reportCount})',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primaryDark,
                ),
              ),
            ),
            if (_reportsExpanded)
              _ReportsList(
                reports: widget.reports,
                isLoading: widget.isLoadingReports,
              ),
          ],
          const SizedBox(height: AppSpacing.s),
          _ActionButtons(
            status: review.status,
            isModerating: widget.isModerating,
            onModerate: widget.onModerate,
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  final ReviewStatus status;

  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    final Color color;
    final String label;
    switch (status) {
      case ReviewStatus.published:
        color = AppColors.success;
        label = 'Published';
        break;
      case ReviewStatus.hidden:
        color = AppColors.warning;
        label = 'Hidden';
        break;
      case ReviewStatus.rejected:
        color = AppColors.error;
        label = 'Rejected';
        break;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadii.pillBorder,
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _FlaggedBadge extends StatelessWidget {
  final int reportCount;

  const _FlaggedBadge({required this.reportCount});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.flag_rounded, size: 14, color: AppColors.error),
        const SizedBox(width: 4),
        Text(
          'Flagged - $reportCount report${reportCount == 1 ? '' : 's'}',
          style: AppTypography.caption.copyWith(
            color: AppColors.error,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}

class _ReportsList extends StatelessWidget {
  final List<ReviewReportModel>? reports;
  final bool isLoading;

  const _ReportsList({required this.reports, required this.isLoading});

  static final DateFormat _dateFormat = DateFormat('MMM d, yyyy');

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: AppSpacing.s),
        child: Center(
          child: SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        ),
      );
    }
    final list = reports ?? const [];
    if (list.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Text(
          'No report details available.',
          style: AppTypography.caption,
        ),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final report in list)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 3),
            child: Text(
              '${report.reason.label} - ${_dateFormat.format(report.createdAt)}'
              '${report.note != null ? ': ${report.note}' : ''}',
              style: AppTypography.caption,
            ),
          ),
      ],
    );
  }
}

class _ActionButtons extends StatelessWidget {
  final ReviewStatus status;
  final bool isModerating;
  final ValueChanged<ReviewModerationAction> onModerate;

  const _ActionButtons({
    required this.status,
    required this.isModerating,
    required this.onModerate,
  });

  @override
  Widget build(BuildContext context) {
    final actions = ReviewModerationAction.values
        .where((a) => a.targetStatus != status)
        .toList();

    return Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xs,
      children: [
        for (final action in actions)
          OutlinedButton(
            key: Key('admin_review_action_${action.name}'),
            onPressed: isModerating ? null : () => onModerate(action),
            style: OutlinedButton.styleFrom(
              foregroundColor: action == ReviewModerationAction.restore
                  ? AppColors.success
                  : AppColors.error,
              side: BorderSide(
                color: action == ReviewModerationAction.restore
                    ? AppColors.success
                    : AppColors.error,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s,
                vertical: AppSpacing.xs,
              ),
              shape: RoundedRectangleBorder(borderRadius: AppRadii.smallBorder),
            ),
            child: Text(
              action.label,
              style: AppTypography.bodySmall.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        if (isModerating)
          const SizedBox(
            width: 16,
            height: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
      ],
    );
  }
}
