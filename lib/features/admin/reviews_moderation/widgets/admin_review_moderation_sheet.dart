import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../reviews/models/review_moderation_action.dart';
import '../../../reviews/models/review_validation.dart';

/// Opens the "reason required" confirmation sheet for a single moderation
/// [action] (Ratings/Reviews v1 Stage 8, v1 §0 decision 12 - "each action
/// requires a reason", including `restore`). Resolves to the trimmed reason
/// string on confirm, or `null` if the admin cancelled/dismissed it.
Future<String?> showAdminReviewModerationSheet(
  BuildContext context, {
  required ReviewModerationAction action,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (context) => AdminReviewModerationSheet(action: action),
  );
}

class AdminReviewModerationSheet extends StatefulWidget {
  final ReviewModerationAction action;

  const AdminReviewModerationSheet({super.key, required this.action});

  @override
  State<AdminReviewModerationSheet> createState() =>
      _AdminReviewModerationSheetState();
}

class _AdminReviewModerationSheetState
    extends State<AdminReviewModerationSheet> {
  final _reasonController = TextEditingController();
  String _reason = '';

  @override
  void dispose() {
    _reasonController.dispose();
    super.dispose();
  }

  bool get _isValid => ReviewValidation.isModerationReasonValid(_reason);

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
            Text(widget.action.label, style: AppTypography.title),
            const SizedBox(height: AppSpacing.s),
            Text(
              'A reason is required and will be recorded in the audit log.',
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            TextField(
              key: const Key('admin_review_moderation_reason_field'),
              controller: _reasonController,
              maxLength: ReviewValidation.moderationReasonMaxLength,
              maxLines: 3,
              autofocus: true,
              onChanged: (value) => setState(() => _reason = value),
              decoration: const InputDecoration(
                labelText: 'Reason',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: AppSpacing.m),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    key: const Key('admin_review_moderation_cancel_button'),
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
                    key: const Key('admin_review_moderation_confirm_button'),
                    onPressed: _isValid
                        ? () => Navigator.of(
                            context,
                          ).pop(_reasonController.text.trim())
                        : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                      disabledBackgroundColor: AppColors.neutralLight,
                      disabledForegroundColor: AppColors.textSecondary,
                      padding: const EdgeInsets.symmetric(
                        vertical: AppSpacing.m,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: AppRadii.mediumBorder,
                      ),
                    ),
                    child: const Text('Confirm'),
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
