import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:printing/printing.dart';
import 'package:provider/provider.dart';

import '../../../../app/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/app_primary_button.dart';
import '../../../../core/widgets/feedback/app_toast.dart';
import '../services/marker_sheet_pdf.dart';
import '../viewmodels/marker_ar_viewmodel.dart';
import '../widgets/marker_ar_calibration_sheet.dart';
import '../widgets/marker_ar_controls.dart';
import '../widgets/marker_ar_debug_overlay.dart';
import '../widgets/marker_ar_object_selector.dart';
import '../widgets/marker_ar_r10_panel.dart';
import '../widgets/marker_ar_status_banner.dart';

/// Tier-2 Marker-AR screen (Phase 9.2 R5) — CameraX + OpenCV ArUco + Filament
/// behind one Android PlatformView, wrapped in TWin-AR-themed chrome.
///
/// Two launch modes, decided by [MarkerArViewModel.isCustomerMode]:
///  * **engine-dev** (debug-only Profile tile): the four-product selector, the
///    debug metrics HUD and the R10 Storage panel are all available;
///  * **customer** (Product Details → prep screen → "Start AR"): one product,
///    no selector, no developer controls — its verified GLB is fetched from
///    Storage on start with the bundled asset as the silent fallback.
class MarkerArView extends StatefulWidget {
  const MarkerArView({super.key});

  @override
  State<MarkerArView> createState() => _MarkerArViewState();
}

class _MarkerArViewState extends State<MarkerArView>
    with WidgetsBindingObserver {
  PermissionStatus? _permission;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _refreshPermission();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshPermission();
      context.read<MarkerArViewModel>().setActive(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      context.read<MarkerArViewModel>().setActive(false);
    }
  }

  Future<void> _refreshPermission() async {
    final s = await Permission.camera.status;
    if (mounted) setState(() => _permission = s);
  }

  Future<void> _requestPermission() async {
    final s = await Permission.camera.request();
    if (mounted) setState(() => _permission = s);
  }

  /// Honest fallback (R7/R8): when the camera can't be used, offer this same
  /// product as a Tier-3 3D preview instead of a dead end. Replaces the AR
  /// route so Back still returns to the preparation screen.
  VoidCallback? _previewFallback(BuildContext context) {
    final args = context.read<MarkerArViewModel>().customerSessionArgs;
    if (args == null) return null;
    return () => Navigator.of(
      context,
    ).pushReplacementNamed(RouteNames.roomArPreview, arguments: args);
  }

  @override
  Widget build(BuildContext context) {
    final s = _permission;
    return Scaffold(
      backgroundColor: AppColors.black,
      body: switch (s) {
        null => const Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
        PermissionStatus() when s.isGranted => const _MarkerArCamera(),
        _ => _PermissionRequest(
          status: s,
          onRequest: _requestPermission,
          onOpenSettings: openAppSettings,
          onRecheck: _refreshPermission,
          onViewPreview: _previewFallback(context),
        ),
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PermissionRequest extends StatelessWidget {
  final PermissionStatus status;
  final VoidCallback onRequest;
  final Future<bool> Function() onOpenSettings;
  final VoidCallback onRecheck;
  final VoidCallback? onViewPreview;

  const _PermissionRequest({
    required this.status,
    required this.onRequest,
    required this.onOpenSettings,
    required this.onRecheck,
    this.onViewPreview,
  });

  @override
  Widget build(BuildContext context) {
    final blocked = status.isPermanentlyDenied || status.isRestricted;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new,
                  color: AppColors.white,
                  size: 20,
                ),
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const Spacer(),
            const Icon(
              Icons.photo_camera_outlined,
              color: AppColors.white,
              size: 44,
            ),
            const SizedBox(height: AppSpacing.m),
            Text(
              'Camera access needed',
              style: AppTypography.headingMedium.copyWith(
                color: AppColors.white,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Room AR uses the rear camera to detect a printed marker and anchor '
              'the piece to your floor. Nothing is recorded or uploaded.',
              style: AppTypography.bodyMedium.copyWith(
                color: AppColors.white.withValues(alpha: 0.8),
                height: 1.4,
              ),
            ),
            const SizedBox(height: AppSpacing.l),
            AppPrimaryButton(
              label: blocked ? 'Open settings' : 'Allow camera',
              onPressed: blocked ? () => onOpenSettings() : onRequest,
            ),
            const SizedBox(height: AppSpacing.xs),
            Wrap(
              spacing: AppSpacing.s,
              children: [
                TextButton(
                  onPressed: onRecheck,
                  child: Text(
                    'Re-check',
                    style: AppTypography.label.copyWith(
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
                if (onViewPreview != null)
                  TextButton(
                    onPressed: onViewPreview,
                    child: Text(
                      'View a 3D preview instead',
                      style: AppTypography.label.copyWith(
                        color: AppColors.primaryLight,
                      ),
                    ),
                  ),
              ],
            ),
            const Spacer(flex: 2),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _MarkerArCamera extends StatefulWidget {
  const _MarkerArCamera();

  @override
  State<_MarkerArCamera> createState() => _MarkerArCameraState();
}

class _MarkerArCameraState extends State<_MarkerArCamera> {
  // Raw gesture bookkeeping — Flutter gesture-arena plumbing only. Every domain
  // decision (tap vs place, ray casting, clamp, facing) is in MarkerArViewModel.
  Offset _start = Offset.zero;
  DateTime _startAt = DateTime.fromMillisecondsSinceEpoch(0);
  double _travel = 0;
  int _maxPointers = 0;
  bool _isDrag = false;
  double _yawAtStart = 0;

  MarkerArViewModel get _vm => context.read<MarkerArViewModel>();

  void _onScaleStart(ScaleStartDetails d) {
    _start = d.localFocalPoint;
    _startAt = DateTime.now();
    _travel = 0;
    _maxPointers = d.pointerCount;
    _isDrag = false;
    _yawAtStart = _vm.yawAtGestureStart;
    _vm.beginDrag();
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    _maxPointers = _maxPointers > d.pointerCount
        ? _maxPointers
        : d.pointerCount;
    final t = (d.localFocalPoint - _start).distance;
    if (t > _travel) _travel = t;

    if (d.pointerCount >= 2) {
      _isDrag = true; // definitely not a tap
      _vm.rotateTo(_yawAtStart + d.rotation);
      return;
    }
    if (_travel <= MarkerArViewModel.tapSlopPx) return;
    _isDrag = true;
    _vm.dragTo(d.localFocalPoint);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final ms = DateTime.now().difference(_startAt).inMilliseconds;
    final wasTap =
        !_isDrag &&
        _maxPointers <= 1 &&
        _travel <= MarkerArViewModel.tapSlopPx &&
        ms <= MarkerArViewModel.tapMaxMs;
    if (wasTap) {
      _vm.placeAt(_start);
    } else {
      _vm.endDrag();
    }
  }

  Future<void> _openMarkerSheet() async {
    try {
      final vm = _vm;
      final png = await vm.markerPng(px: 1400);
      final pdf = await buildMarkerSheetPdf(
        markerPng: png,
        markerMm: vm.config.markerMm,
        dict: vm.config.dict,
        markerId: vm.config.markerId,
      );
      await Printing.layoutPdf(
        onLayout: (_) async => pdf,
        name:
            'twin_ar_room_ar_marker_${vm.config.markerMm.toStringAsFixed(0)}mm',
      );
    } catch (e) {
      if (mounted) AppToast.error(context, 'Marker sheet failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    // Built once and handed to the Consumer as its `child`, so the native
    // PlatformView subtree is NOT rebuilt on every per-frame ViewModel
    // notification (matches the previous `const AndroidView`). `nativeMode` is
    // immutable for the ViewModel's lifetime.
    final platformView = _MarkerPlatformView(
      mode: context.read<MarkerArViewModel>().nativeMode,
    );
    return Consumer<MarkerArViewModel>(
      child: platformView,
      builder: (context, vm, platformViewChild) {
        // Customer flow: a device that can't run the engine gets an honest
        // full-screen message and a way back — never a frozen camera. Wait for
        // the native config handshake so the fallback config isn't misread as
        // a failure during the first frame.
        if (vm.isCustomerMode && vm.engineConfigResolved && vm.hasEngineError) {
          final args = vm.customerSessionArgs;
          return _EngineUnavailable(
            message: vm.engineErrorMessage,
            onViewPreview: args == null
                ? null
                : () => Navigator.of(context).pushReplacementNamed(
                    RouteNames.roomArPreview,
                    arguments: args,
                  ),
          );
        }
        // Storage delivery definitively failed and this product has no
        // compiled-in bundled asset to fall back to (true for every
        // product except the four originally-bundled ones) — an honest
        // full-screen state, never a substitute model.
        if (vm.isCustomerMode && vm.customerModelUnavailable) {
          return const _ModelUnavailable();
        }
        return Stack(
          fit: StackFit.expand,
          children: [
            // Native camera + OpenCV tracking + Filament model overlay.
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  vm.setSurfaceSize(constraints.biggest);
                  return GestureDetector(
                    behavior: HitTestBehavior.translucent,
                    onScaleStart: _onScaleStart,
                    onScaleUpdate: _onScaleUpdate,
                    onScaleEnd: _onScaleEnd,
                    child: platformViewChild,
                  );
                },
              ),
            ),

            // Top chrome: back + honest status.
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: Column(
                children: [
                  MarkerArStatusBanner(
                    track: vm.track,
                    heldMs: vm.frame.heldMs,
                    markerSidePx: vm.frame.markerSidePx,
                    calibrated: vm.isCalibrated,
                    markerMm: vm.calibration.markerSizeMm,
                    objectName: vm.productTitle,
                    engineError: vm.hasEngineError,
                    engineErrorMessage: vm.engineErrorMessage,
                  ),
                ],
              ),
            ),
            Positioned(
              top: 0,
              left: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(AppSpacing.xs),
                  child: _CircleIconButton(
                    icon: Icons.close,
                    onTap: () => Navigator.of(context).maybePop(),
                  ),
                ),
              ),
            ),

            // Debug metrics — development builds only, never a customer control.
            if (vm.debugHudVisible)
              Positioned(
                left: AppSpacing.xs,
                bottom: 210,
                right: AppSpacing.xxl,
                child: MarkerArDebugOverlay(
                  frame: vm.frame,
                  config: vm.config,
                  calibration: vm.calibration,
                  object: vm.object,
                  offX: vm.offX,
                  offZ: vm.offZ,
                  yaw: vm.yaw,
                  placed: vm.placementSet,
                ),
              ),
            if (vm.debugAvailable)
              Positioned(
                right: AppSpacing.xs,
                top: MediaQuery.of(context).padding.top + 4,
                child: Column(
                  children: [
                    _CircleIconButton(
                      icon: vm.debugHudVisible
                          ? Icons.bug_report
                          : Icons.bug_report_outlined,
                      onTap: vm.toggleDebugHud,
                    ),
                    if (vm.r10Available) ...[
                      const SizedBox(height: AppSpacing.xs),
                      _CircleIconButton(
                        icon: Icons.cloud_download_outlined,
                        onTap: () => MarkerArR10Panel.show(context, vm),
                      ),
                    ],
                  ],
                ),
              ),

            // Transient flash message.
            if (vm.flash != null)
              Positioned(
                left: 0,
                right: 0,
                bottom: 220,
                child: Center(child: _FlashChip(text: vm.flash!)),
              ),

            // Bottom controls.
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: MarkerArControls(
                yaw: vm.yaw,
                calibrated: vm.isCalibrated,
                onYaw: vm.setYaw,
                onFaceMe: vm.faceMe,
                onReset: vm.reset,
                onOpenMarkerSheet: _openMarkerSheet,
                onOpenCalibration: () =>
                    MarkerArCalibrationSheet.show(context, vm),
                selector: vm.isCustomerMode
                    ? _ProductChip(icon: vm.productIcon, label: vm.productTitle)
                    : MarkerArObjectSelector(
                        objects: vm.selectableObjects,
                        selected: vm.object,
                        onSelected: vm.selectObject,
                      ),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The Tier-2 Marker-AR PlatformView.
///
/// [mode] (the native renderer slot key — `chair`/`table`/`lamp`/`sofa` for a
/// bundled product, or the live Firestore product id otherwise) is passed as a
/// **creation param**, not a post-creation `setObject` channel call: the
/// native renderer selects the right slot synchronously while it is being
/// constructed, so a product with no bundled counterpart renders *nothing*
/// until its verified GLB arrives — never the chair. A post-creation call can
/// be dropped if it races the PlatformView's own creation (which is exactly
/// what left the chair on screen on the first cold launch). [mode] is
/// immutable for a session, so rebuilding this widget never recreates the
/// platform view. Mirrors Tier 1's `ArCorePlatformView`.
class _MarkerPlatformView extends StatelessWidget {
  final String mode;
  const _MarkerPlatformView({required this.mode});

  @override
  Widget build(BuildContext context) {
    return AndroidView(
      viewType: 'twin_ar/room_ar/marker/view',
      creationParams: <String, dynamic>{'mode': mode},
      creationParamsCodec: const StandardMessageCodec(),
      // Guaranteed-post-creation re-send of the Storage-delivered external
      // model (its file path isn't known until the download/cache resolve
      // finishes). Harmless/idempotent if nothing raced.
      onPlatformViewCreated: (_) =>
          context.read<MarkerArViewModel>().onPlatformViewCreated(),
    );
  }
}

class _CircleIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  const _CircleIconButton({required this.icon, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.black.withValues(alpha: 0.45),
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 40,
          height: 40,
          child: Icon(icon, color: AppColors.white, size: 20),
        ),
      ),
    );
  }
}

class _FlashChip extends StatelessWidget {
  final String text;
  const _FlashChip({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primaryDark.withValues(alpha: 0.95),
        borderRadius: AppRadii.pillBorder,
      ),
      child: Text(
        text,
        style: AppTypography.bodySmall.copyWith(color: AppColors.white),
      ),
    );
  }
}

/// Read-only "which product" chip for the customer flow — replaces the
/// four-product selector so there is no way to switch away from the piece the
/// customer opened.
class _ProductChip extends StatelessWidget {
  final IconData icon;
  final String label;
  const _ProductChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 40),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.35),
        borderRadius: AppRadii.pillBorder,
        border: Border.all(color: AppColors.white.withValues(alpha: 0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: AppColors.white),
          const SizedBox(width: AppSpacing.xxs),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTypography.label.copyWith(
                color: AppColors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Full-screen honest state for the customer flow when Storage delivery has
/// definitively failed for a product with no compiled-in bundled fallback
/// (every product except the four originally-bundled ones). Never a
/// substitute model — the camera/engine may be perfectly fine here, there is
/// simply nothing verified to show yet.
class _ModelUnavailable extends StatelessWidget {
  const _ModelUnavailable();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: AppColors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.view_in_ar_outlined,
                color: AppColors.white,
                size: 44,
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                'This 3D model isn\'t available right now',
                style: AppTypography.headingMedium.copyWith(
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'We couldn\'t load this product\'s model. Please check your '
                'connection and try again later.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.white.withValues(alpha: 0.8),
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
        ),
      ),
    );
  }
}

/// Full-screen honest state for the customer flow when the AR engine can't run
/// on this device (e.g. OpenCV failed to load). Never a frozen camera.
class _EngineUnavailable extends StatelessWidget {
  final String? message;
  final VoidCallback? onViewPreview;
  const _EngineUnavailable({this.message, this.onViewPreview});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.black,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  icon: const Icon(
                    Icons.arrow_back_ios_new,
                    color: AppColors.white,
                    size: 20,
                  ),
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              ),
              const Spacer(),
              const Icon(
                Icons.view_in_ar_outlined,
                color: AppColors.white,
                size: 44,
              ),
              const SizedBox(height: AppSpacing.m),
              Text(
                'Camera AR isn\'t available on this device',
                style: AppTypography.headingMedium.copyWith(
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                onViewPreview != null
                    ? 'You can still view this piece as an interactive 3D '
                          'model instead.'
                    : (message ??
                          'This device can\'t run the AR engine right now. You '
                              'can still browse the product and its photos.'),
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.white.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.l),
              if (onViewPreview != null) ...[
                AppPrimaryButton(
                  label: 'View 3D preview',
                  onPressed: onViewPreview!,
                ),
                const SizedBox(height: AppSpacing.xs),
                TextButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  child: Text(
                    'Go back',
                    style: AppTypography.label.copyWith(
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
              ] else
                AppPrimaryButton(
                  label: 'Go back',
                  onPressed: () => Navigator.of(context).maybePop(),
                ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
