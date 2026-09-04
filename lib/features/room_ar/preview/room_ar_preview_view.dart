import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/app_primary_button.dart';
import 'room_ar_preview_channel.dart';
import 'room_ar_preview_viewmodel.dart';

/// Tier-3 Interactive 3D Preview screen (Phase 9.2 R7).
///
/// A no-camera, no-marker orbit viewer for one approved product, reached when
/// runtime routing (R8) picks Tier 3 — or as the honest fallback from the
/// Tier-2 camera screen. Clearly labelled "Interactive 3D preview", themed to
/// the app, with orbit / pan / pinch-zoom / reset and no developer controls.
class RoomArPreviewView extends StatefulWidget {
  const RoomArPreviewView({super.key});

  @override
  State<RoomArPreviewView> createState() => _RoomArPreviewViewState();
}

class _RoomArPreviewViewState extends State<RoomArPreviewView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final vm = context.read<RoomArPreviewViewModel>();
    if (state == AppLifecycleState.resumed) {
      vm.setActive(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      vm.setActive(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.surface, AppColors.neutralLight],
          ),
        ),
        child: SafeArea(
          child: Consumer<RoomArPreviewViewModel>(
            builder: (context, vm, _) {
              if (vm.renderFailed) return _Failed(title: vm.productTitle);
              return Stack(
                children: [
                  Positioned.fill(child: _PreviewStage(mode: vm.object.mode)),
                  if (vm.isPreparing)
                    const Positioned.fill(child: _Preparing()),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _TopBar(title: vm.productTitle),
                  ),
                  if (vm.notice != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 96,
                      child: Center(child: _NoticeChip(text: vm.notice!)),
                    ),
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _BottomBar(
                      dims: vm.dimensionsM,
                      onReset: vm.resetView,
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ── the interactive stage ───────────────────────────────────────────────────

class _PreviewStage extends StatefulWidget {
  const _PreviewStage({required this.mode});

  /// The product's native mode string ("chair"/"table"/"lamp"/"sofa"). Passed
  /// as a PlatformView creation param so the renderer starts on the right
  /// model — a later `setModel` call can lose the race with view creation.
  final String mode;

  @override
  State<_PreviewStage> createState() => _PreviewStageState();
}

class _PreviewStageState extends State<_PreviewStage> {
  RoomArPreviewViewModel get _vm => context.read<RoomArPreviewViewModel>();

  Offset _lastFocal = Offset.zero;
  int _pointers = 0;
  double _lastScale = 1.0;

  void _onScaleStart(ScaleStartDetails d) {
    _lastFocal = d.localFocalPoint;
    _pointers = d.pointerCount;
    _lastScale = 1.0;
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _pointers = d.pointerCount > _pointers ? d.pointerCount : _pointers;
    final delta = d.localFocalPoint - _lastFocal;
    _lastFocal = d.localFocalPoint;

    // pinch → zoom
    if (d.scale != 1.0) {
      final step = d.scale / _lastScale;
      _lastScale = d.scale;
      if (step.isFinite && step > 0) _vm.zoom(step);
    }
    // two fingers → pan, one finger → orbit
    if (d.pointerCount >= 2) {
      _vm.pan(delta.dx, delta.dy);
    } else if (delta != Offset.zero) {
      _vm.orbit(delta.dx, delta.dy);
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: _onScaleStart,
      onScaleUpdate: _onScaleUpdate,
      onDoubleTap: _vm.resetView,
      child: AndroidView(
        viewType: RoomArPreviewChannel.viewType,
        creationParams: <String, dynamic>{'mode': widget.mode},
        creationParamsCodec: const StandardMessageCodec(),
      ),
    );
  }
}

// ── chrome ──────────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final String title;
  const _TopBar({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.xs,
        AppSpacing.m,
        0,
      ),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(
              Icons.arrow_back_ios_new,
              color: AppColors.textPrimary,
              size: 20,
            ),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.label.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Row(
                  children: [
                    const Icon(
                      Icons.threed_rotation,
                      size: 13,
                      color: AppColors.textSecondary,
                    ),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(
                        'Interactive 3D preview · not camera AR',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.caption.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  final ({double w, double h, double d}) dims;
  final VoidCallback onReset;
  const _BottomBar({required this.dims, required this.onReset});

  @override
  Widget build(BuildContext context) {
    String cm(double m) => (m * 100).round().toString();
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        AppSpacing.s + MediaQuery.of(context).padding.bottom,
      ),
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.neutralMediumLight)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'Drag to rotate · two fingers to pan · pinch to zoom · '
            'double-tap to reset',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            'Shown at actual size · W ${cm(dims.w)} · D ${cm(dims.d)} · '
            'H ${cm(dims.h)} cm',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(
                'Reset view',
                style: AppTypography.label.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _NoticeChip extends StatelessWidget {
  final String text;
  const _NoticeChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.textPrimary.withValues(alpha: 0.85),
        borderRadius: AppRadii.pillBorder,
      ),
      child: Text(
        text,
        textAlign: TextAlign.center,
        style: AppTypography.caption.copyWith(color: AppColors.white),
      ),
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.surface.withValues(alpha: 0.6),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: AppSpacing.s),
            Text('Preparing the 3D model…', style: AppTypography.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _Failed extends StatelessWidget {
  final String title;
  const _Failed({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_new,
                color: AppColors.textPrimary,
                size: 20,
              ),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
          ),
          const Spacer(),
          const Icon(
            Icons.view_in_ar_outlined,
            color: AppColors.textSecondary,
            size: 44,
          ),
          const SizedBox(height: AppSpacing.m),
          Text(
            'The 3D preview couldn\'t be shown',
            style: AppTypography.headingMedium.copyWith(
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'This device couldn\'t display the 3D model for $title. You can '
            'still browse its photos and details.',
            style: AppTypography.bodyMedium.copyWith(
              color: AppColors.textSecondary,
              height: 1.4,
            ),
          ),
          const SizedBox(height: AppSpacing.l),
          AppPrimaryButton(
            label: 'Go back',
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          const Spacer(flex: 2),
        ],
      ),
    );
  }
}
