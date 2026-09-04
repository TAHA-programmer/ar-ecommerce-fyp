import 'package:flutter/material.dart';

import '../../../../core/models/product/product_ar_metadata.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../models/admin_ar_model_candidate.dart';
import '../viewmodels/ar_media_management_viewmodel.dart';
import 'admin_media_components.dart';

/// Phase 9.2 R16 — production Room-AR model management for the selected
/// product. Replaces the pre-9.2 mock "choose a fake .glb + scale" card.
///
/// One card, driven entirely by [ArMediaManagementViewModel]'s
/// [AdminRoomArModelStatus]. Every mutation is *staged* and committed by the
/// screen's existing "Save Changes" / "Save Configuration" button — matching
/// the established AR & Media stage-then-save model and the product form's
/// image workflow.
class AdminRoomArModelCard extends StatelessWidget {
  const AdminRoomArModelCard({
    super.key,
    required this.viewModel,
    required this.onPreview,
  });

  final ArMediaManagementViewModel viewModel;

  /// Navigate to the admin 3D preview (staged local file or committed model).
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final status = viewModel.roomArModelStatus;
    return AdminMediaCard(
      key: const Key('admin_room_ar_model_card'),
      icon: Icons.view_in_ar_outlined,
      title: 'Room AR (3D Model)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _StatusChip(status: status),
          ),
          const SizedBox(height: AppSpacing.s),
          if (viewModel.modelValidationError != null) ...[
            _ErrorBanner(message: viewModel.modelValidationError!),
            const SizedBox(height: AppSpacing.s),
          ],
          if (viewModel.modelValidationError == null &&
              viewModel.modelWorkflowNote != null) ...[
            _InfoBanner(message: viewModel.modelWorkflowNote!),
            const SizedBox(height: AppSpacing.s),
          ],
          if (viewModel.isValidatingModel) ...[
            const _BusyRow(label: 'Validating 3D model…'),
            const SizedBox(height: AppSpacing.s),
          ],
          if (viewModel.isUploadingModel) ...[
            _UploadProgress(value: viewModel.modelUploadProgress),
            const SizedBox(height: AppSpacing.s),
          ],
          ..._bodyFor(context, status),
          const SizedBox(height: AppSpacing.m),
          _legend(),
        ],
      ),
    );
  }

  List<Widget> _bodyFor(BuildContext context, AdminRoomArModelStatus status) {
    switch (status) {
      case AdminRoomArModelStatus.stagedUpload:
        return [_CandidateEditor(viewModel: viewModel, onPreview: onPreview)];
      case AdminRoomArModelStatus.stagedDeletion:
        return [
          _DangerNote(
            text:
                'This model will be permanently deleted from Storage and the '
                'catalogue when you save. The customer entry point is already '
                'off.',
          ),
          const SizedBox(height: AppSpacing.s),
          OutlinedButton.icon(
            key: const Key('room_ar_cancel_deletion'),
            onPressed: viewModel.cancelStagedModelDeletion,
            icon: const Icon(Icons.undo),
            label: const Text('Keep the model'),
          ),
        ];
      case AdminRoomArModelStatus.noModel:
        return [
          Text(
            'No 3D model uploaded. Select a binary glTF (.glb) authored to the '
            'TWin scale contract (+Y up, front −Z, floor-centred, real metres).',
            style: AppTypography.bodySmall,
          ),
          const SizedBox(height: AppSpacing.s),
          _pickButton(context, label: 'Select GLB model'),
        ];
      case AdminRoomArModelStatus.broken:
        return [
          Text(
            'The stored model contract is invalid and is not shown to '
            'customers. Fix it by uploading a corrected model.',
            style: AppTypography.bodySmall.copyWith(color: AppColors.error),
          ),
          const SizedBox(height: AppSpacing.xs),
          ...viewModel.committedModelIssues.map(
            (issue) => Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('•  $issue', style: AppTypography.caption),
            ),
          ),
          const SizedBox(height: AppSpacing.s),
          _pickButton(context, label: 'Replace model'),
        ];
      case AdminRoomArModelStatus.live:
      case AdminRoomArModelStatus.disabled:
      case AdminRoomArModelStatus.stagedToggle:
      case AdminRoomArModelStatus.readyNotApproved:
        final ar = viewModel.committedArMetadata!;
        return [
          if (status == AdminRoomArModelStatus.readyNotApproved) ...[
            _InfoBanner(
              message:
                  'This model is valid, but "${viewModel.selectedProduct?.title ?? 'this product'}" '
                  'is not on the approved customer Room-AR list yet — customers '
                  'still cannot launch it. Releasing a new product end-to-end '
                  '(Storage rules + a physical pass) is a separate Phase 9.2 '
                  'step.',
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          _MetadataTable(metadata: ar),
          const SizedBox(height: AppSpacing.m),
          _EntryPointToggle(
            enabled: viewModel.roomArEntryPointEnabled,
            customerReachable: viewModel.productIsCustomerApproved,
            onChanged: viewModel.setRoomArEntryPointEnabled,
          ),
          const SizedBox(height: AppSpacing.s),
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                key: const Key('room_ar_preview_button'),
                onPressed: viewModel.canPreviewModel ? onPreview : null,
                icon: const Icon(Icons.threed_rotation, size: 18),
                label: const Text('Preview'),
              ),
              OutlinedButton.icon(
                key: const Key('room_ar_replace_button'),
                onPressed: () => _pick(context),
                icon: const Icon(Icons.upload_outlined, size: 18),
                label: const Text('Replace model'),
              ),
              if (viewModel.canStageModelDeletion)
                OutlinedButton.icon(
                  key: const Key('room_ar_delete_button'),
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Delete model'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                ),
            ],
          ),
          if (!viewModel.roomArEntryPointEnabled &&
              !viewModel.canStageModelDeletion)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                'Save the disabled state before you can permanently delete the '
                'model.',
                style: AppTypography.caption,
              ),
            ),
        ];
    }
  }

  Widget _pickButton(BuildContext context, {required String label}) =>
      ElevatedButton.icon(
        key: const Key('room_ar_select_glb_button'),
        onPressed: () => _pick(context),
        icon: const Icon(Icons.folder_open_outlined),
        label: Text(label),
      );

  Future<void> _pick(BuildContext context) async {
    await viewModel.pickAndValidateModel();
    if (!context.mounted) return;
    if (viewModel.stagedCandidate != null) {
      AppToast.success(context, 'Model validated — review, then Save.');
    } else if (viewModel.modelValidationError != null) {
      AppToast.error(context, viewModel.modelValidationError!);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.largeBorder,
          side: const BorderSide(color: AppColors.error),
        ),
        title: const Text('Permanently delete this model?'),
        content: const Text(
          'The GLB is removed from Storage and every AR field is cleared from '
          'the product. This cannot be undone — you would need to upload a new '
          'model. The change is applied when you save.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Stage deletion',
              style: AppTypography.label.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true) viewModel.stageModelDeletion();
  }

  Widget _legend() => Wrap(
    spacing: AppSpacing.s,
    runSpacing: AppSpacing.xs,
    children: const [
      _LegendItem(color: AppColors.success, label: 'Live'),
      _LegendItem(color: AppColors.warning, label: 'Disabled / staged'),
      _LegendItem(color: AppColors.info, label: 'Uploading'),
      _LegendItem(color: AppColors.error, label: 'Invalid / needs fix'),
    ],
  );
}

// ── candidate editor ────────────────────────────────────────────────────────

class _CandidateEditor extends StatefulWidget {
  const _CandidateEditor({required this.viewModel, required this.onPreview});

  final ArMediaManagementViewModel viewModel;
  final VoidCallback onPreview;

  @override
  State<_CandidateEditor> createState() => _CandidateEditorState();
}

class _CandidateEditorState extends State<_CandidateEditor> {
  late final TextEditingController _w;
  late final TextEditingController _d;
  late final TextEditingController _h;
  late final TextEditingController _scale;

  AdminArModelCandidate get _c => widget.viewModel.stagedCandidate!;

  @override
  void initState() {
    super.initState();
    _w = TextEditingController(text: _c.widthM.toStringAsFixed(3));
    _d = TextEditingController(text: _c.depthM.toStringAsFixed(3));
    _h = TextEditingController(text: _c.heightM.toStringAsFixed(3));
    _scale = TextEditingController(text: _c.scale.toStringAsFixed(2));
  }

  @override
  void dispose() {
    _w.dispose();
    _d.dispose();
    _h.dispose();
    _scale.dispose();
    super.dispose();
  }

  Future<void> _applyDimensions() async {
    final w = double.tryParse(_w.text.trim());
    final d = double.tryParse(_d.text.trim());
    final h = double.tryParse(_h.text.trim());
    final ok = await widget.viewModel.updateStagedDimensions(
      widthM: w,
      depthM: d,
      heightM: h,
    );
    if (!mounted) return;
    if (!ok && widget.viewModel.modelValidationError != null) {
      AppToast.error(context, widget.viewModel.modelValidationError!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.viewModel.stagedCandidate;
    if (c == null) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.all(AppSpacing.s),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: AppRadii.mediumBorder,
            border: Border.all(color: AppColors.neutralMediumLight),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                c.file.uri.pathSegments.isEmpty
                    ? 'Selected model'
                    : c.file.uri.pathSegments.last,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                '${c.sizeMib.toStringAsFixed(2)} MB · glb · will upload as '
                'model-v${c.targetVersion}',
                style: AppTypography.caption,
              ),
              Text(
                'SHA-256 ${c.sha256.substring(0, 16)}…',
                style: AppTypography.caption,
              ),
              Text(
                'Measured  W ${_cm(c.measuredM.width)} · '
                'D ${_cm(c.measuredM.depth)} · H ${_cm(c.measuredM.height)} cm',
                style: AppTypography.caption,
              ),
              Row(
                children: [
                  Icon(
                    c.floorCentred ? Icons.check_circle : Icons.error_outline,
                    size: 14,
                    color: c.floorCentred ? AppColors.success : AppColors.error,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    c.floorCentred
                        ? 'Floor-centred'
                        : 'Not floor-centred (base not at height 0)',
                    style: AppTypography.caption,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.m),
        Text('Confirm real dimensions (metres)', style: AppTypography.label),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(child: _numField('Width (X)', _w)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _numField('Depth (Z)', _d)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(child: _numField('Height (Y)', _h)),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Row(
          children: [
            Expanded(child: _numField('Scale', _scale, onSubmit: _applyScale)),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: OutlinedButton(
                key: const Key('room_ar_apply_dimensions'),
                onPressed: _applyDimensions,
                child: const Text('Check fit'),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          c.dimensionsMatchMeasured
              ? 'Entered dimensions match the model geometry.'
              : 'Entered dimensions differ from the measured geometry — press '
                    '“Check fit” to re-validate before saving.',
          style: AppTypography.caption.copyWith(
            color: c.dimensionsMatchMeasured
                ? AppColors.primaryDark
                : AppColors.warning,
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            OutlinedButton.icon(
              key: const Key('room_ar_preview_button'),
              onPressed: widget.onPreview,
              icon: const Icon(Icons.threed_rotation, size: 18),
              label: const Text('Preview'),
            ),
            OutlinedButton.icon(
              key: const Key('room_ar_discard_candidate'),
              onPressed: widget.viewModel.discardStagedModel,
              icon: const Icon(Icons.close, size: 18),
              label: const Text('Discard'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Nothing is uploaded until you save. The current customer model '
          '(if any) keeps working until this replacement is verified.',
          style: AppTypography.caption,
        ),
      ],
    );
  }

  Future<void> _applyScale() async {
    if (!widget.viewModel.updateStagedScale(_scale.text) && mounted) {
      AppToast.error(context, 'Scale must be a number between 0 and 10.');
    }
  }

  Widget _numField(
    String label,
    TextEditingController controller, {
    Future<void> Function()? onSubmit,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.caption),
        const SizedBox(height: 2),
        TextField(
          controller: controller,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          style: AppTypography.bodyMedium,
          onSubmitted: (_) => onSubmit?.call(),
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: AppRadii.smallBorder),
          ),
        ),
      ],
    );
  }

  static String _cm(double m) => (m * 100).toStringAsFixed(1);
}

// ── small pieces ────────────────────────────────────────────────────────────

class _MetadataTable extends StatelessWidget {
  const _MetadataTable({required this.metadata});
  final ProductArMetadata metadata;

  @override
  Widget build(BuildContext context) {
    String cm(double m) => (m * 100).toStringAsFixed(0);
    final rows = <(String, String)>[
      ('Format', metadata.format),
      ('Version', 'model-v${metadata.modelVersion}'),
      (
        'Real size',
        'W ${cm(metadata.widthM)} · D ${cm(metadata.depthM)} · '
            'H ${cm(metadata.heightM)} cm',
      ),
      ('Scale', metadata.scale.toStringAsFixed(2)),
      ('Scale contract', metadata.scaleContract),
      ('Storage', metadata.storagePath),
      ('SHA-256', '${metadata.sha256.substring(0, 20)}…'),
      (
        'Integrity',
        metadata.isRenderable
            ? 'Contract valid · verified on every device load'
            : 'Contract invalid',
      ),
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.mediumBorder,
        border: Border.all(color: AppColors.neutralMediumLight),
      ),
      child: Column(
        children: [
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 96,
                    child: Text(label, style: AppTypography.caption),
                  ),
                  Expanded(
                    child: Text(
                      value,
                      style: AppTypography.caption.copyWith(
                        color: AppColors.textPrimary,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryPointToggle extends StatelessWidget {
  const _EntryPointToggle({
    required this.enabled,
    required this.customerReachable,
    required this.onChanged,
  });
  final bool enabled;
  final bool customerReachable;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final onCopy = customerReachable
        ? 'On — a supported customer device can launch AR.'
        : 'On (admin intent) — customers still cannot launch this until the '
              'product is approved.';
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customer "View in Your Room" entry point',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                enabled
                    ? onCopy
                    : 'Off — the model is retained; no AR launch is shown.',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        Switch(
          key: const Key('room_ar_entry_point_toggle'),
          value: enabled,
          onChanged: onChanged,
          activeThumbColor: AppColors.primary,
        ),
      ],
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.status});
  final AdminRoomArModelStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      AdminRoomArModelStatus.live => (
        'Live · customers can view in AR',
        AppColors.success,
        Icons.check_circle,
      ),
      AdminRoomArModelStatus.readyNotApproved => (
        'Model ready · not yet released to customers',
        AppColors.warning,
        Icons.hourglass_bottom,
      ),
      AdminRoomArModelStatus.disabled => (
        'Disabled · model retained',
        AppColors.warning,
        Icons.pause_circle_outline,
      ),
      AdminRoomArModelStatus.broken => (
        'Needs attention · contract invalid',
        AppColors.error,
        Icons.error_outline,
      ),
      AdminRoomArModelStatus.noModel => (
        'No model uploaded',
        AppColors.neutralDark,
        Icons.info_outline,
      ),
      AdminRoomArModelStatus.stagedUpload => (
        'New model staged · save to upload',
        AppColors.info,
        Icons.cloud_upload_outlined,
      ),
      AdminRoomArModelStatus.stagedToggle => (
        'Entry-point change staged · save to apply',
        AppColors.warning,
        Icons.sync_alt,
      ),
      AdminRoomArModelStatus.stagedDeletion => (
        'Deletion staged · save to apply',
        AppColors.error,
        Icons.delete_forever_outlined,
      ),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: AppRadii.pillBorder,
        border: Border.all(color: color),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: color),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              style: AppTypography.caption.copyWith(
                color: AppColors.textPrimary,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.s),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.1),
      borderRadius: AppRadii.mediumBorder,
      border: Border.all(color: AppColors.error),
    ),
    child: Row(
      children: [
        const Icon(Icons.error_outline, color: AppColors.error, size: 18),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(message, style: AppTypography.caption)),
      ],
    ),
  );
}

class _InfoBanner extends StatelessWidget {
  const _InfoBanner({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.s),
    decoration: BoxDecoration(
      color: AppColors.warning.withValues(alpha: 0.12),
      borderRadius: AppRadii.mediumBorder,
      border: Border.all(color: AppColors.warning),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.info_outline, color: AppColors.warning, size: 18),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(message, style: AppTypography.caption)),
      ],
    ),
  );
}

class _DangerNote extends StatelessWidget {
  const _DangerNote({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.s),
    decoration: BoxDecoration(
      color: AppColors.error.withValues(alpha: 0.08),
      borderRadius: AppRadii.mediumBorder,
      border: Border.all(color: AppColors.error),
    ),
    child: Text(text, style: AppTypography.bodySmall),
  );
}

class _BusyRow extends StatelessWidget {
  const _BusyRow({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      const SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
      const SizedBox(width: AppSpacing.xs),
      Text(label, style: AppTypography.bodySmall),
    ],
  );
}

class _UploadProgress extends StatelessWidget {
  const _UploadProgress({required this.value});
  final double value;

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('Uploading model…', style: AppTypography.caption),
          Text('${(value * 100).round()}%', style: AppTypography.caption),
        ],
      ),
      const SizedBox(height: 4),
      ClipRRect(
        borderRadius: BorderRadius.circular(4),
        child: LinearProgressIndicator(value: value == 0 ? null : value),
      ),
    ],
  );
}

class _LegendItem extends StatelessWidget {
  const _LegendItem({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(Icons.circle, color: color, size: 10),
      const SizedBox(width: 4),
      Text(label, style: AppTypography.caption),
    ],
  );
}
