import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../room_ar/preview/room_ar_preview_channel.dart';
import '../viewmodels/admin_ar_model_preview_viewmodel.dart';

/// Phase 9.2 R16 — admin-only 3D preview of a staged or committed Room-AR
/// model. Reuses the physically-approved native orbit renderer
/// (`RoomArPreviewChannel`, key `"admin"`); no camera, no marker.
class AdminArModelPreviewView extends StatefulWidget {
  const AdminArModelPreviewView({super.key});

  @override
  State<AdminArModelPreviewView> createState() =>
      _AdminArModelPreviewViewState();
}

class _AdminArModelPreviewViewState extends State<AdminArModelPreviewView>
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
    final vm = context.read<AdminArModelPreviewViewModel>();
    vm.setActive(state == AppLifecycleState.resumed);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: AppBar(
        title: const Text('Model preview (admin)'),
        titleTextStyle: AppTypography.title,
      ),
      body: Consumer<AdminArModelPreviewViewModel>(
        builder: (context, vm, _) {
          if (vm.renderFailed) {
            return _Failed(title: vm.productTitle, notice: vm.notice);
          }
          final path = vm.resolvedFilePath;
          return Column(
            children: [
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [AppColors.surface, AppColors.neutralLight],
                          ),
                        ),
                        // The native view is created ONLY once we have the
                        // exact file, which is handed over as a creation param
                        // (no dropped `setModel` race → the right model shows
                        // first, every time).
                        child: path == null
                            ? const SizedBox.expand()
                            : _Stage(filePath: path),
                      ),
                    ),
                    if (vm.isPreparing)
                      const Positioned.fill(child: _Preparing()),
                    if (vm.notice != null && !vm.isPreparing)
                      Positioned(
                        left: AppSpacing.m,
                        right: AppSpacing.m,
                        bottom: AppSpacing.m,
                        child: _Chip(text: vm.notice!),
                      ),
                  ],
                ),
              ),
              _BottomBar(dims: vm.dimensionsM, onReset: vm.resetView),
            ],
          );
        },
      ),
    );
  }
}

class _Stage extends StatefulWidget {
  const _Stage({required this.filePath});

  /// The exact `.glb` on disk — handed to the native renderer as a creation
  /// param so it loads the right model at construction.
  final String filePath;

  @override
  State<_Stage> createState() => _StageState();
}

class _StageState extends State<_Stage> {
  AdminArModelPreviewViewModel get _vm =>
      context.read<AdminArModelPreviewViewModel>();

  Offset _lastFocal = Offset.zero;
  double _lastScale = 1.0;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onScaleStart: (d) {
        _lastFocal = d.localFocalPoint;
        _lastScale = 1.0;
      },
      onScaleUpdate: (d) {
        final delta = d.localFocalPoint - _lastFocal;
        _lastFocal = d.localFocalPoint;
        if (d.scale != 1.0) {
          final step = d.scale / _lastScale;
          _lastScale = d.scale;
          if (step.isFinite && step > 0) _vm.zoom(step);
        }
        if (d.pointerCount >= 2) {
          _vm.pan(delta.dx, delta.dy);
        } else if (delta != Offset.zero) {
          _vm.orbit(delta.dx, delta.dy);
        }
      },
      onDoubleTap: _vm.resetView,
      child: AndroidView(
        viewType: RoomArPreviewChannel.viewType,
        creationParams: <String, dynamic>{
          'mode': 'admin',
          'path': widget.filePath,
        },
        creationParamsCodec: const StandardMessageCodec(),
        onPlatformViewCreated: (_) => _vm.onRendererCreated(),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.dims, required this.onReset});
  final ({double w, double h, double d}) dims;
  final VoidCallback onReset;

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
            'Interactive 3D preview · not camera AR · '
            'drag to rotate, two fingers to pan, pinch to zoom',
            textAlign: TextAlign.center,
            style: AppTypography.caption.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Declared size · W ${cm(dims.w)} · D ${cm(dims.d)} · '
            'H ${cm(dims.h)} cm',
            style: AppTypography.caption.copyWith(color: AppColors.textPrimary),
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              onPressed: onReset,
              icon: const Icon(Icons.restart_alt, size: 18),
              label: const Text('Reset view'),
            ),
          ),
        ],
      ),
    );
  }
}

class _Preparing extends StatelessWidget {
  const _Preparing();

  @override
  Widget build(BuildContext context) => ColoredBox(
    color: AppColors.surface.withValues(alpha: 0.6),
    child: const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CircularProgressIndicator(color: AppColors.primary),
          SizedBox(height: AppSpacing.s),
          Text('Preparing the 3D model…'),
        ],
      ),
    ),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
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

class _Failed extends StatelessWidget {
  const _Failed({required this.title, this.notice});
  final String title;
  final String? notice;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(AppSpacing.l),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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
          notice ?? 'This device couldn\'t display the 3D model for $title.',
          style: AppTypography.bodyMedium.copyWith(
            color: AppColors.textSecondary,
            height: 1.4,
          ),
        ),
        const SizedBox(height: AppSpacing.l),
        OutlinedButton(
          onPressed: () => Navigator.of(context).maybePop(),
          child: const Text('Go back'),
        ),
      ],
    ),
  );
}
