import 'package:flutter/material.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../models/review_report_reason.dart';
import '../models/review_validation.dart';

/// What the customer chose in [ReviewReportSheet] - handed back to
/// `ProductReviewsSection`'s caller via `Navigator.pop`.
class ReviewReportSubmission {
  final ReviewReportReason reason;
  final String? note;

  const ReviewReportSubmission({required this.reason, this.note});
}

/// Opens the "Report this review" bottom sheet (Ratings/Reviews v1 Stage 8).
/// Resolves to the customer's chosen [ReviewReportSubmission], or `null` if
/// they cancelled/dismissed it without submitting.
Future<ReviewReportSubmission?> showReviewReportSheet(BuildContext context) {
  return showModalBottomSheet<ReviewReportSubmission>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => const ReviewReportSheet(),
  );
}

/// The reason-picker + optional note form itself - a small, self-contained
/// bottom sheet (v1 §0 decision 10/11: one report per user per review,
/// never auto-hidden). A repeat report of the same review by the same
/// customer is a harmless no-op server-side (`reportReview`), so this sheet
/// never needs to know whether the customer already reported it.
class ReviewReportSheet extends StatefulWidget {
  const ReviewReportSheet({super.key});

  @override
  State<ReviewReportSheet> createState() => _ReviewReportSheetState();
}

class _ReviewReportSheetState extends State<ReviewReportSheet> {
  ReviewReportReason _reason = ReviewReportReason.spam;
  final _noteController = TextEditingController();

  @override
  void dispose() {
    _noteController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: AppSpacing.l,
          right: AppSpacing.l,
          top: AppSpacing.l,
          bottom: AppSpacing.l + MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Report this review', style: AppTypography.title),
            const SizedBox(height: AppSpacing.s),
            Text(
              'Tell us why - our team will take a look.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                for (final reason in ReviewReportReason.values)
                  _ReasonChip(
                    key: Key('review_report_reason_chip_${reason.name}'),
                    label: reason.label,
                    isSelected: reason == _reason,
                    onTap: () => setState(() => _reason = reason),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              key: const Key('review_report_note_field'),
              controller: _noteController,
              maxLength: ReviewValidation.reportNoteMaxLength,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Additional details (optional)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('review_report_cancel_button'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      side: const BorderSide(color: AppColors.primary),
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.m,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.mediumBorder,
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: AppSpacing.s),
                Expanded(
                  child: ElevatedButton(
                    key: const Key('review_report_submit_button'),
                    onPressed: () {
                      final note = _noteController.text.trim();
                      Navigator.of(context).pop(
                        ReviewReportSubmission(
                          reason: _reason,
                          note: note.isEmpty ? null : note,
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.m,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.mediumBorder,
                      ),
                    ),
                    child: const Text('Submit'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonChip extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _ReasonChip({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.surface,
          borderRadius: AppRadii.pillBorder,
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.neutralMediumLight,
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: isSelected ? AppColors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
