import 'package:flutter/material.dart';

import '../../../../core/models/product/product_vto_metadata.dart';
import '../../../../core/models/product/product_vto_model_type.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../models/admin_vto_garment_candidate.dart';
import '../viewmodels/ar_media_management_viewmodel.dart';
import 'admin_media_components.dart';

/// Phase 9.3 Stage 3 — production Virtual Try-On garment-asset management for
/// the selected clothing product. Replaced the pre-9.3 mock configuration card
/// (which staged a fake asset name and never touched Storage).
///
/// One card, driven entirely by [ArMediaManagementViewModel]'s
/// [AdminVtoAssetStatus]. Every mutation is *staged* and committed by the
/// screen's existing "Save Changes" / "Save Configuration" button — the exact
/// stage-then-save model of [AdminRoomArModelCard].
///
/// The customer try-on flow (Phase 9.3 Stage 5) is live: a fully-configured,
/// published, entry-point-enabled product genuinely shows customers "Try It
/// On" and can generate a real preview. The status copy here says "Live"
/// only when that is actually true — see [AdminVtoAssetStatus].
///
/// "Preview Garment" is deliberately **informational**: it shows the uploaded
/// 2-D garment reference image only and never itself starts or affects a
/// customer's Virtual Try-On session (that is a separate, billable model
/// call the customer triggers from Product Details).
class AdminVtoGarmentCard extends StatelessWidget {
  const AdminVtoGarmentCard({super.key, required this.viewModel});

  final ArMediaManagementViewModel viewModel;

  @override
  Widget build(BuildContext context) {
    final product = viewModel.selectedProduct;
    final status = viewModel.vtoAssetStatus;
    return AdminMediaCard(
      key: const Key('admin_vto_garment_card'),
      icon: Icons.checkroom_outlined,
      title: 'Virtual Try-On (Garment Images)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: _StatusChip(status: status),
          ),
          const SizedBox(height: AppSpacing.s),
          if (viewModel.garmentValidationError != null) ...[
            _Banner(
              message: viewModel.garmentValidationError!,
              color: AppColors.error,
              icon: Icons.error_outline,
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          if (viewModel.garmentValidationError == null &&
              viewModel.vtoWorkflowNote != null) ...[
            _Banner(
              message: viewModel.vtoWorkflowNote!,
              color: AppColors.warning,
              icon: Icons.info_outline,
            ),
            const SizedBox(height: AppSpacing.s),
          ],
          if (viewModel.isValidatingGarment) ...[
            const _BusyRow(label: 'Validating image…'),
            const SizedBox(height: AppSpacing.s),
          ],
          if (viewModel.isUploadingGarment) ...[
            _UploadProgress(value: viewModel.garmentUploadProgress),
            const SizedBox(height: AppSpacing.s),
          ],
          Text(
            "A visual preview only. It shows a garment's look and colour on "
            'a person, and can never be used to judge fit or size.',
            style: AppTypography.caption,
          ),
          const SizedBox(height: AppSpacing.m),
          if (status == AdminVtoAssetStatus.stagedDeletion)
            _deletionBody(context)
          else ...[
            _categoryDropdown(),
            const SizedBox(height: AppSpacing.m),
            if (product != null && status == AdminVtoAssetStatus.broken) ...[
              _brokenNote(),
              const SizedBox(height: AppSpacing.s),
            ],
            _modelTypeDropdown(product?.vtoModelType),
            const SizedBox(height: AppSpacing.m),
            Text('Garment image per colour', style: AppTypography.label),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              'Upload one clean garment photo for every colour this product '
              'sells. The optional "Default" image is used only for a colour '
              'with no image of its own, when the colourways look identical.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.s),
            for (final slot in viewModel.vtoSlots) ...[
              _GarmentSlotRow(viewModel: viewModel, slot: slot),
              const SizedBox(height: AppSpacing.s),
            ],
            if (viewModel.committedVtoMetadata != null) ...[
              const SizedBox(height: AppSpacing.xs),
              _EntryPointToggle(
                enabled: viewModel.vtoEntryPointEnabled,
                customerReachable: viewModel.vtoProductIsCustomerApproved,
                onChanged: viewModel.setVtoEntryPointEnabled,
              ),
              const SizedBox(height: AppSpacing.s),
              if (viewModel.canStageVtoDeletion)
                OutlinedButton.icon(
                  key: const Key('vto_delete_button'),
                  onPressed: () => _confirmDelete(context),
                  icon: const Icon(Icons.delete_outline, size: 18),
                  label: const Text('Remove Virtual Try-On'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppColors.error,
                  ),
                )
              else if (!viewModel.vtoEntryPointEnabled)
                Text(
                  'Save the disabled state before you can permanently remove '
                  'the Virtual Try-On configuration.',
                  style: AppTypography.caption,
                ),
            ],
          ],
          const SizedBox(height: AppSpacing.m),
          _legend(),
        ],
      ),
    );
  }

  Widget _deletionBody(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Container(
        padding: const EdgeInsets.all(AppSpacing.s),
        decoration: BoxDecoration(
          color: AppColors.error.withValues(alpha: 0.08),
          borderRadius: AppRadii.mediumBorder,
          border: Border.all(color: AppColors.error),
        ),
        child: Text(
          'Every Virtual Try-On garment image will be permanently deleted from '
          'Storage and all VTO fields cleared from the product when you save. '
          'The stored entry point is already off.',
          style: AppTypography.bodySmall,
        ),
      ),
      const SizedBox(height: AppSpacing.s),
      OutlinedButton.icon(
        key: const Key('vto_cancel_deletion'),
        onPressed: viewModel.cancelStagedVtoDeletion,
        icon: const Icon(Icons.undo),
        label: const Text('Keep the configuration'),
      ),
    ],
  );

  Widget _brokenNote() => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(
        'The stored Virtual Try-On config is invalid and is not usable. Fix it '
        'by re-uploading the affected images.',
        style: AppTypography.bodySmall.copyWith(color: AppColors.error),
      ),
      const SizedBox(height: AppSpacing.xxs),
      ...viewModel.committedVtoIssues.map(
        (issue) => Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text('•  $issue', style: AppTypography.caption),
        ),
      ),
    ],
  );

  Widget _categoryDropdown() {
    return _Dropdown<String>(
      label: 'Garment category',
      hint: 'Select a category',
      value: viewModel.vtoGarmentCategory,
      items: kVtoGarmentCategoryOptions,
      labelFor: _capitalized,
      onChanged: viewModel.setVtoGarmentCategory,
    );
  }

  Widget _modelTypeDropdown(ProductVtoModelType? value) {
    return _Dropdown<ProductVtoModelType>(
      label: 'Model type',
      hint: 'Select Male or Female',
      value: value,
      items: ProductVtoModelType.values,
      labelFor: (v) => v.displayName,
      onChanged: viewModel.setVtoModelType,
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: AppRadii.largeBorder,
          side: const BorderSide(color: AppColors.error),
        ),
        title: const Text('Remove Virtual Try-On?'),
        content: const Text(
          'Every garment image is removed from Storage and all VTO fields are '
          'cleared from the product. This cannot be undone — you would need to '
          're-upload the images. The change is applied when you save.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(
              'Stage removal',
              style: AppTypography.label.copyWith(color: AppColors.error),
            ),
          ),
        ],
      ),
    );
    if (ok == true) viewModel.stageVtoDeletion();
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

  static String _capitalized(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';
}

// ── per-slot row ────────────────────────────────────────────────────────────

class _GarmentSlotRow extends StatelessWidget {
  const _GarmentSlotRow({required this.viewModel, required this.slot});

  final ArMediaManagementViewModel viewModel;
  final String slot;

  bool get _isDefault => slot == kVtoDefaultSlot;

  String get _title => _isDefault
      ? 'Default (any colour without its own image)'
      : '${slot[0].toUpperCase()}${slot.substring(1)}';

  @override
  Widget build(BuildContext context) {
    final candidate = viewModel.vtoCandidateForSlot(slot);
    final committed = viewModel.committedVtoAssetForSlot(slot);
    // A committed asset whose stored path is NOT exactly this product's own
    // expected path for the slot (cross-product / hand-edited / wrong version):
    // never previewed or trusted, must be replaced.
    final committedIsForeign = viewModel.committedGarmentPathIsForeign(slot);
    return Container(
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: AppRadii.mediumBorder,
        border: Border.all(color: AppColors.neutralMediumLight),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  _title,
                  style: AppTypography.bodyMedium.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (candidate != null)
                _Pill(
                  text: 'staged v${candidate.targetVersion}',
                  color: AppColors.info,
                )
              else if (committed != null && committedIsForeign)
                _Pill(text: 'foreign path', color: AppColors.error)
              else if (committed != null && committed.isRenderable)
                _Pill(text: 'v${committed.version}', color: AppColors.success)
              else if (committed != null)
                _Pill(text: 'invalid', color: AppColors.error),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          _preview(context, candidate, committed),
          const SizedBox(height: AppSpacing.xs),
          if (candidate != null) ...[
            Text(
              '${candidate.width}×${candidate.height} · '
              '${candidate.sizeMib.toStringAsFixed(2)} MB · '
              '${candidate.contentType == 'image/png' ? 'PNG' : 'JPEG'} · '
              'SHA-256 ${candidate.sha256.substring(0, 12)}…',
              style: AppTypography.caption,
            ),
            if (candidate.isBelowRecommendedResolution)
              Text(
                'Below the recommended '
                '${VtoGarmentAsset.recommendedMinLongEdgePx}px — it will work '
                'but the preview may look soft.',
                style: AppTypography.caption.copyWith(color: AppColors.warning),
              ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                _button(
                  context,
                  key: 'vto_replace_$slot',
                  icon: Icons.upload_outlined,
                  label: 'Choose a different image',
                  onTap: () => _pick(context),
                ),
                _button(
                  context,
                  key: 'vto_discard_$slot',
                  icon: Icons.close,
                  label: 'Discard',
                  onTap: () => viewModel.discardStagedGarment(slot),
                ),
              ],
            ),
          ] else if (committed != null) ...[
            Text(
              committedIsForeign
                  ? 'This colour\'s stored image path does not belong to this '
                        'product — it will not be shown or reused. Replace it.'
                  : committed.isRenderable
                  ? '${committed.width}×${committed.height} · '
                        '${committed.contentType == 'image/png' ? 'PNG' : 'JPEG'} · '
                        'stored'
                  : 'This image\'s stored contract is invalid — replace it.',
              style: AppTypography.caption.copyWith(
                color: (committedIsForeign || !committed.isRenderable)
                    ? AppColors.error
                    : AppColors.textSecondary,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.xs,
              runSpacing: AppSpacing.xs,
              children: [
                if (viewModel.canPreviewCommittedGarment(slot))
                  _button(
                    context,
                    key: 'vto_preview_$slot',
                    icon: Icons.visibility_outlined,
                    label: 'Preview Garment',
                    onTap: () => _previewCommitted(context),
                  ),
                _button(
                  context,
                  key: 'vto_replace_$slot',
                  icon: Icons.upload_outlined,
                  label: 'Replace',
                  onTap: () => _pick(context),
                ),
              ],
            ),
          ] else ...[
            Text(
              _isDefault
                  ? 'Optional. No default image set.'
                  : 'No image for this colour yet.',
              style: AppTypography.caption,
            ),
            const SizedBox(height: AppSpacing.xs),
            _button(
              context,
              key: 'vto_add_$slot',
              icon: Icons.add_photo_alternate_outlined,
              label: 'Add image',
              onTap: () => _pick(context),
            ),
          ],
        ],
      ),
    );
  }

  Widget _preview(
    BuildContext context,
    AdminVtoGarmentCandidate? candidate,
    VtoGarmentAsset? committed,
  ) {
    Widget child;
    if (candidate != null) {
      child = Image.file(candidate.file, fit: BoxFit.contain);
    } else if (committed != null &&
        viewModel.canPreviewCommittedGarment(slot)) {
      child = FutureBuilder(
        future: viewModel.downloadCommittedGarmentBytes(slot),
        builder: (context, snap) {
          if (snap.connectionState != ConnectionState.done) {
            return const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            );
          }
          if (snap.hasError || snap.data == null) {
            return Center(
              child: Text('Preview unavailable', style: AppTypography.caption),
            );
          }
          return Image.memory(snap.data!, fit: BoxFit.contain);
        },
      );
    } else {
      child = Center(
        child: Icon(
          Icons.image_outlined,
          color: AppColors.neutralMedium,
          size: 32,
        ),
      );
    }
    return AdminMediaPreview(
      label: candidate != null
          ? 'Staged image'
          : (committed != null ? 'Stored image' : 'No image'),
      child: child,
    );
  }

  Future<void> _pick(BuildContext context) async {
    await viewModel.pickAndValidateGarment(slot);
    if (!context.mounted) return;
    if (viewModel.vtoCandidateForSlot(slot) != null) {
      AppToast.success(context, 'Image validated — review, then Save.');
    } else if (viewModel.garmentValidationError != null) {
      AppToast.error(context, viewModel.garmentValidationError!);
    }
  }

  Future<void> _previewCommitted(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: AppRadii.largeBorder),
        title: Text('$_title — garment image'),
        content: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 320),
                child: FutureBuilder(
                  future: viewModel.downloadCommittedGarmentBytes(slot),
                  builder: (context, snap) {
                    if (snap.connectionState != ConnectionState.done) {
                      return const Padding(
                        padding: EdgeInsets.all(AppSpacing.l),
                        child: CircularProgressIndicator(),
                      );
                    }
                    if (snap.hasError || snap.data == null) {
                      return Text(
                        'Could not load this image.',
                        style: AppTypography.bodySmall,
                      );
                    }
                    return Image.memory(snap.data!, fit: BoxFit.contain);
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.s),
              Text(
                "This previews the uploaded garment reference image only. It "
                "doesn't start or affect a customer's Virtual Try-On session.",
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _button(
    BuildContext context, {
    required String key,
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) => OutlinedButton.icon(
    key: Key(key),
    onPressed: onTap,
    icon: Icon(icon, size: 16),
    label: Text(label),
  );
}

// ── small pieces ────────────────────────────────────────────────────────────

class _Dropdown<T> extends StatelessWidget {
  const _Dropdown({
    required this.label,
    required this.value,
    required this.items,
    required this.labelFor,
    required this.onChanged,
    this.hint,
  });

  final String label;
  final T? value;
  final List<T> items;
  final String Function(T) labelFor;
  final ValueChanged<T> onChanged;
  final String? hint;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: AppTypography.bodySmall),
        const SizedBox(height: AppSpacing.xxs),
        DropdownButtonFormField<T>(
          initialValue: value,
          isExpanded: true,
          hint: hint == null ? null : Text(hint!),
          items: items
              .map(
                (item) => DropdownMenuItem<T>(
                  value: item,
                  child: Text(labelFor(item)),
                ),
              )
              .toList(),
          onChanged: (v) {
            if (v != null) onChanged(v);
          },
          style: AppTypography.bodyMedium,
          decoration: InputDecoration(
            isDense: true,
            border: OutlineInputBorder(borderRadius: AppRadii.mediumBorder),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.mediumBorder,
              borderSide: const BorderSide(color: AppColors.neutralMediumLight),
            ),
          ),
        ),
      ],
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.xs,
      vertical: AppSpacing.xxs,
    ),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.14),
      borderRadius: AppRadii.pillBorder,
      border: Border.all(color: color),
    ),
    child: Text(
      text,
      style: AppTypography.caption.copyWith(fontWeight: FontWeight.w600),
    ),
  );
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
        ? 'On. Customers can try this product on right now.'
        : 'On, but not yet effective. A colour is uncovered or the product '
              'is unpublished; try-on will work for customers as soon as '
              "that's resolved.";
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Customer "Try It On" entry point',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                enabled
                    ? onCopy
                    : "Off. The images stay saved, but customers can't try "
                          'this product on.',
                style: AppTypography.caption,
              ),
            ],
          ),
        ),
        Switch(
          key: const Key('vto_entry_point_toggle'),
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
  final AdminVtoAssetStatus status;

  @override
  Widget build(BuildContext context) {
    final (label, color, icon) = switch (status) {
      AdminVtoAssetStatus.live => (
        'Live · customers can try this on',
        AppColors.success,
        Icons.check_circle_outline,
      ),
      AdminVtoAssetStatus.readyNotApproved => (
        'Configuration incomplete · a colour is uncovered or the product is '
            'unpublished',
        AppColors.warning,
        Icons.hourglass_bottom,
      ),
      AdminVtoAssetStatus.disabled => (
        'Disabled · images retained',
        AppColors.warning,
        Icons.pause_circle_outline,
      ),
      AdminVtoAssetStatus.broken => (
        'Needs attention · config invalid',
        AppColors.error,
        Icons.error_outline,
      ),
      AdminVtoAssetStatus.noAsset => (
        'No garment images uploaded',
        AppColors.neutralDark,
        Icons.info_outline,
      ),
      AdminVtoAssetStatus.stagedUpload => (
        'Changes staged · save to upload',
        AppColors.info,
        Icons.cloud_upload_outlined,
      ),
      AdminVtoAssetStatus.stagedToggle => (
        'Entry-point change staged · save to apply',
        AppColors.warning,
        Icons.sync_alt,
      ),
      AdminVtoAssetStatus.stagedDeletion => (
        'Removal staged · save to apply',
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

class _Banner extends StatelessWidget {
  const _Banner({
    required this.message,
    required this.color,
    required this.icon,
  });
  final String message;
  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(AppSpacing.s),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.1),
      borderRadius: AppRadii.mediumBorder,
      border: Border.all(color: color),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(width: AppSpacing.xs),
        Expanded(child: Text(message, style: AppTypography.caption)),
      ],
    ),
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
          Text('Uploading garment images…', style: AppTypography.caption),
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
