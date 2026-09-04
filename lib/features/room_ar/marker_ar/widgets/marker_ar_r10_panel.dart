import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../model_delivery/room_ar_model_state.dart';
import '../models/marker_ar_object.dart';
import '../viewmodels/marker_ar_viewmodel.dart';

/// Phase 9.2 R10 — **debug-only** Firebase Storage GLB delivery verification
/// surface. Compiled/reachable only when `kDebugMode` and a
/// `RoomArModelService` has been attached (see `MarkerArViewModel.r10Available`).
///
/// For each of the four approved products it exposes, end to end, the states
/// R10 has to be tested against: bundled fallback, downloading, verified cache,
/// last-known-good cache, integrity/bounds rejection, offline/failure, retry —
/// and installs a verified external file into the native renderer.
///
/// Presented as a proper TWin-AR bottom sheet: a grab handle, a fixed header,
/// and a scrollable body capped at 85% of the screen height so it can never
/// grow off the top. Nothing here ships to a customer build.
class MarkerArR10Panel extends StatelessWidget {
  const MarkerArR10Panel({super.key, required this.viewModel});

  final MarkerArViewModel viewModel;

  static Future<void> show(BuildContext context, MarkerArViewModel viewModel) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
      ),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadii.large),
      ),
      builder: (_) => MarkerArR10Panel(viewModel: viewModel),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: ListenableBuilder(
        listenable: viewModel,
        builder: (context, _) {
          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // grab handle
              Center(
                child: Container(
                  margin: const EdgeInsets.only(
                    top: AppSpacing.s,
                    bottom: AppSpacing.xs,
                  ),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.neutralMediumLight,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),

              // fixed header
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.l,
                  AppSpacing.xs,
                  AppSpacing.l,
                  AppSpacing.s,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(
                          Icons.cloud_download_outlined,
                          size: 18,
                          color: AppColors.primaryDark,
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Expanded(
                          child: Text(
                            'Storage model delivery',
                            style: AppTypography.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          'R10 · dev',
                          style: AppTypography.caption.copyWith(
                            color: AppColors.primaryDark,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      'Fetches each GLB from Storage by object path, verifies '
                      'magic bytes / length / structure / SHA-256 / bounding box '
                      '(±3 %), caches it, then hands the verified file to the '
                      'renderer. Bundled GLBs remain the fallback.',
                      style: AppTypography.bodySmall.copyWith(height: 1.4),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                      visualDensity: VisualDensity.compact,
                      activeThumbColor: AppColors.primary,
                      value: viewModel.r10FallbackToBundled,
                      title: Text(
                        'Fall back to the bundled GLB on any remote failure',
                        style: AppTypography.bodySmall,
                      ),
                      onChanged: (v) => viewModel.r10FallbackToBundled = v,
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),

              // scrollable body — capped by the sheet's maxHeight constraint
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.l,
                    AppSpacing.s,
                    AppSpacing.l,
                    AppSpacing.l,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final product in MarkerArObject.values) ...[
                        _ProductRow(viewModel: viewModel, product: product),
                        if (product != MarkerArObject.values.last)
                          const Divider(height: AppSpacing.l),
                      ],
                      const SizedBox(height: AppSpacing.s),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: Text(
                            'Done',
                            style: AppTypography.label.copyWith(
                              color: AppColors.primaryDark,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductRow extends StatelessWidget {
  const _ProductRow({required this.viewModel, required this.product});

  final MarkerArViewModel viewModel;
  final MarkerArObject product;

  @override
  Widget build(BuildContext context) {
    final state = viewModel.r10StateFor(product);
    final source = viewModel.r10ActiveSourceFor(product);
    final history = viewModel.r10HistoryFor(product);
    final busy = viewModel.r10IsBusy(product);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(product.icon, size: 18, color: AppColors.textPrimary),
            const SizedBox(width: AppSpacing.xs),
            Expanded(
              child: Text(
                product.displayName,
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (source != null) ...[
              const SizedBox(width: AppSpacing.xs),
              _SourceBadge(source: source),
            ],
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          state.debugLabel,
          style: AppTypography.bodySmall.copyWith(
            color: switch (state) {
              RoomArModelIntegrityRejected() ||
              RoomArModelFailed() => AppColors.error,
              RoomArModelOffline() => AppColors.warning,
              RoomArModelReady() => AppColors.success,
              _ => AppColors.textSecondary,
            },
          ),
        ),
        if (history.length > 1) ...[
          const SizedBox(height: AppSpacing.xxs),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(AppSpacing.xs),
            decoration: BoxDecoration(
              color: AppColors.neutralLight,
              borderRadius: AppRadii.smallBorder,
            ),
            child: Text(
              history.join('\n'),
              style: AppTypography.caption.copyWith(
                fontFamily: 'monospace',
                height: 1.35,
              ),
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: 0,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _CompactButton(
              icon: busy ? null : Icons.download,
              busy: busy,
              label: history.isEmpty ? 'Resolve' : 'Retry',
              color: AppColors.primaryDark,
              onPressed: busy ? null : () => viewModel.r10Resolve(product),
            ),
            _CompactButton(
              icon: Icons.cached,
              label: 'Evict cache',
              color: AppColors.textSecondary,
              onPressed: busy ? null : () => viewModel.r10EvictCache(product),
            ),
            if (source != null)
              _CompactButton(
                icon: Icons.inventory_2_outlined,
                label: 'Use bundled',
                color: AppColors.textSecondary,
                onPressed: busy
                    ? null
                    : () => viewModel.r10UseBundledModel(product),
              ),
          ],
        ),
      ],
    );
  }
}

class _CompactButton extends StatelessWidget {
  const _CompactButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.icon,
    this.busy = false,
  });

  final String label;
  final Color color;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs,
          vertical: 4,
        ),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
      ),
      icon: busy
          ? const SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon, size: 16),
      label: Text(
        label,
        style: AppTypography.label.copyWith(color: color, fontSize: 13),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final RoomArModelSource source;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (source) {
      RoomArModelSource.freshDownload => ('downloaded', AppColors.success),
      RoomArModelSource.verifiedCache => ('cache', AppColors.primaryDark),
      RoomArModelSource.lastKnownGood => ('last-good', AppColors.warning),
      RoomArModelSource.bundledFallback => ('bundled', AppColors.textSecondary),
    };
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 2,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: AppRadii.pillBorder,
      ),
      child: Text(
        label,
        style: AppTypography.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
