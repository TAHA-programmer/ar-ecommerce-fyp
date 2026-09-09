import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';

import '../../../../app/routes/route_names.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../../../../core/widgets/buttons/app_primary_button.dart';
import '../services/room_arcore_channel.dart';
import '../viewmodels/room_arcore_viewmodel.dart';

// Phase 9.2 R6 physical smoke-test finding #10 (tracker §32) — why
// GestureDetector's Tap+Scale pairing (finding #9, tracker §31) STILL never
// reliably placed anything, and the final architecture.
//
// §31 added a dedicated `TapGestureRecognizer` (`onTapDown`/`onTapUp`)
// alongside the existing `ScaleGestureRecognizer`, reasoning that Tap would
// win a clean tap and Scale would win a real drag. The very next physical
// test proved that wrong: `tapDown` climbed reliably (0→3→5→8) but
// `tapsSent` stayed 0 — Tap's `onTapDown` fired every time, `onTapUp` never
// did — while `gStart`/`gUpd` (Scale) climbed on what were, per the
// customer, ordinary taps inside a stable, correctly-detected plane.
//
// Root cause, read from Flutter's actual SDK source (not assumed):
//  - `BaseTapGestureRecognizer`'s own class doc (`tap.dart`) states a tap
//    "is accepted only when it is the last member of the arena" — Tap
//    *never* proactively declares itself the winner; it only ever wins by
//    everyone else losing.
//  - `ScaleGestureRecognizer`, by contrast, proactively calls
//    `resolve(GestureDisposition.accepted)` (`scale.dart`,
//    `_advanceStateMachine`) the instant movement crosses its own small
//    slop threshold — a threshold ordinary finger-contact jitter crosses on
//    almost every real touch.
//  - `GestureArenaManager._resolve` (`arena.dart`): once the arena has
//    closed (immediately after the down event finishes dispatching — which
//    happens well before any later move event), any member calling
//    `resolve(accepted)` triggers `_resolveInFavorOf`, which **immediately
//    rejects every other member** — including Tap, mid-flight, before it
//    can ever reach its own up-event/last-member-standing win condition.
//  - So in practice: Scale wins almost every real touch, not just genuine
//    drags — Tap+Scale do not coexist safely for this interaction model.
//    (A real, general Flutter pitfall, not specific to this screen.)
//
// Fix: dropped Flutter's gesture-arena/recognizer system for this widget
// entirely. `_RoomArCoreSceneState` now uses a `Listener` (raw
// `onPointerDown`/`onPointerMove`/`onPointerUp`/`onPointerCancel`) and
// hand-tracks every active pointer itself — no recognizer competes for or
// can "steal" a pointer sequence, so there is nothing left to race.
// Classification is simple and fully under this class's own control:
// before anything is placed, a completed single-pointer sequence whose
// total travel never exceeded `RoomArCoreViewModel.tapSlopPx` is a tap
// (`placeAt`); a second pointer touching down at any point permanently
// disqualifies that sequence from ever placing (multi-touch can never
// trigger initial placement); once real single-pointer movement exceeds
// that same slop with something already placed, it's a drag
// (`beginDrag`/`dragTo`/`endDrag`); two pointers, any time, drive rotate
// (`rotateTo`) via the angle between them.

/// Identifies the single interaction `Listener` that owns placement/
/// reposition/rotate — exposed (not a private key) purely so tests can
/// find it unambiguously via `find.byKey`, since `find.byType(Listener)`
/// could plausibly match other low-level listeners in the tree.
const placementGestureDetectorKey = ValueKey('room_arcore_placement_gesture');

/// Tier-1 markerless-ARCore screen (Phase 9.2 R6) — a real ARCore camera +
/// plane-detection + hit-test/anchor session behind one Android PlatformView,
/// wrapped in TWin-AR-themed chrome. One product, no selector, no developer
/// controls — exactly the customer-mode contract Tier 2/3 already use.
class RoomArCoreView extends StatefulWidget {
  const RoomArCoreView({super.key});

  @override
  State<RoomArCoreView> createState() => _RoomArCoreViewState();
}

class _RoomArCoreViewState extends State<RoomArCoreView>
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
      context.read<RoomArCoreViewModel>().setActive(true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      context.read<RoomArCoreViewModel>().setActive(false);
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

  VoidCallback _previewFallback(BuildContext context) {
    final args = context.read<RoomArCoreViewModel>().fallbackPreviewArgs;
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
        PermissionStatus() when s.isGranted => const _RoomArCoreScene(),
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

class _RoomArCoreScene extends StatefulWidget {
  const _RoomArCoreScene();

  @override
  State<_RoomArCoreScene> createState() => _RoomArCoreSceneState();
}

class _RoomArCoreSceneState extends State<_RoomArCoreScene> {
  // Raw per-pointer position tracking — every domain decision (place vs
  // drag vs rotate) still lives in RoomArCoreViewModel; this class only
  // classifies the raw pointer stream. See the class-level doc comment for
  // why this replaced GestureDetector's Tap+Scale recognizers.
  final Map<int, Offset> _pointers = <int, Offset>{};
  int? _primaryPointer;
  Offset _primaryDownPosition = Offset.zero;
  bool _isTapCandidate = true;
  bool _dragActive = false;
  double _yawAtRotateStart = 0;
  double _rotateStartAngle = 0;

  RoomArCoreViewModel get _vm => context.read<RoomArCoreViewModel>();

  double _angleBetween(Offset a, Offset b) =>
      math.atan2(b.dy - a.dy, b.dx - a.dx);

  void _onPointerDown(PointerDownEvent e) {
    final wasEmpty = _pointers.isEmpty;
    _pointers[e.pointer] = e.localPosition;

    if (wasEmpty) {
      // First finger of a brand-new gesture sequence — provisionally a tap
      // until proven otherwise (real movement, or a second finger).
      _primaryPointer = e.pointer;
      _primaryDownPosition = e.localPosition;
      _isTapCandidate = true;
      _dragActive = false;
    } else if (_pointers.length == 2) {
      // A second finger arriving at ANY point permanently disqualifies this
      // whole sequence from ever placing — multi-touch can never trigger
      // initial placement, regardless of what happens after.
      _isTapCandidate = false;
      if (_dragActive) {
        _vm.endDrag();
        _dragActive = false;
      }
      final pts = _pointers.values.toList(growable: false);
      _rotateStartAngle = _angleBetween(pts[0], pts[1]);
      _yawAtRotateStart = _vm.yawAtGestureStart;
    }
    // A 3rd+ simultaneous pointer is tracked (for continuity of the
    // rotate-angle math) but doesn't change classification further.
  }

  void _onPointerMove(PointerMoveEvent e) {
    if (!_pointers.containsKey(e.pointer)) return;
    _pointers[e.pointer] = e.localPosition;

    if (_pointers.length >= 2) {
      final pts = _pointers.values.toList(growable: false);
      final angle = _angleBetween(pts[0], pts[1]);
      _vm.rotateTo(_yawAtRotateStart + (angle - _rotateStartAngle));
      return;
    }

    if (e.pointer != _primaryPointer) return;
    final travel = (e.localPosition - _primaryDownPosition).distance;
    if (_isTapCandidate) {
      // Natural finger jitter under the slop threshold still counts as a
      // tap — only real movement past it reclassifies this as a drag.
      if (travel <= RoomArCoreViewModel.tapSlopPx) return;
      _isTapCandidate = false;
      if (_vm.hasAnchor) {
        _vm.beginDrag();
        _dragActive = true;
      }
    }
    if (_dragActive) {
      _vm.dragTo(e.localPosition);
    }
  }

  void _onPointerUp(PointerUpEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer != _primaryPointer) {
      // A secondary pointer lifted first (e.g. one finger of a two-finger
      // rotate) — whatever mode is already active continues with the
      // pointer(s) still down; nothing to finalize yet.
      return;
    }
    if (_pointers.isEmpty) {
      // The last pointer of this whole sequence lifted.
      if (_isTapCandidate) {
        // Native `placeAt` already handles both cases identically: nothing
        // placed yet -> place there; already placed -> replace the anchor
        // at this fresh hit (RoomArCoreView.kt's own doc comment).
        _vm.placeAt(e.localPosition);
      } else if (_dragActive) {
        _vm.endDrag();
      }
      _resetGesture();
    } else {
      // The primary pointer lifted while others remain down (mid two-finger
      // rotate) — promote the next tracked pointer to primary so a
      // subsequent single-finger continuation (drag) has a sane baseline.
      // Tap candidacy was already permanently disqualified when the second
      // pointer first touched down, so this can never re-arm placement.
      _primaryPointer = _pointers.keys.first;
      _primaryDownPosition = _pointers[_primaryPointer]!;
    }
  }

  void _onPointerCancel(PointerCancelEvent e) {
    _pointers.remove(e.pointer);
    if (e.pointer == _primaryPointer) {
      if (_dragActive) _vm.endDrag();
      _resetGesture();
      _pointers.clear();
    }
  }

  void _resetGesture() {
    _primaryPointer = null;
    _isTapCandidate = true;
    _dragActive = false;
  }

  @override
  Widget build(BuildContext context) {
    // Phase 9.2 R6 physical smoke-test (tracker §27): the entire screen —
    // including the AndroidView + its wrapping interaction layer — used to
    // live inside one Consumer<RoomArCoreViewModel>, which rebuilds on
    // EVERY ARCore frame (~60/sec, since RoomArCoreViewModel notifies on
    // every native frame event). Rebuilding that subtree that aggressively
    // is a plausible way to lose an in-progress touch gesture — a physical
    // test showed taps never even registering (a `tapsSent` counter stayed
    // at 0 through repeated taps) regardless of which native camera-layer
    // implementation was underneath, which pointed away from the native
    // side and toward exactly this kind of Flutter-side churn. Fixed by
    // reading only the two rarely-changing bools that gate a full-screen
    // replacement here (`context.select` only rebuilds this outer widget
    // when either actually changes, not every frame), and moving the
    // AndroidView + Listener fully outside any per-frame-rebuilding scope —
    // only the small text banners below still update live, in their own
    // narrow Consumer.
    final hasEngineError = context.select<RoomArCoreViewModel, bool>(
      (vm) => vm.hasEngineError,
    );
    final modelUnavailable = context.select<RoomArCoreViewModel, bool>(
      (vm) => vm.customerModelUnavailable,
    );

    if (hasEngineError) {
      final vm = _vm;
      return _EngineUnavailable(
        message: vm.engineErrorMessage,
        onViewPreview: () => Navigator.of(context).pushReplacementNamed(
          RouteNames.roomArPreview,
          arguments: vm.fallbackPreviewArgs,
        ),
      );
    }
    // Storage delivery definitively failed and this product has no
    // compiled-in bundled asset to fall back to — an honest full-screen
    // state, never a substitute model.
    if (modelUnavailable) {
      return const _ModelUnavailable();
    }

    final vm = _vm;
    return Stack(
      fit: StackFit.expand,
      children: [
        // The AndroidView + its raw-pointer Listener — built once per
        // screen (only rebuilt if the two rarely-changing bools above
        // flip), never torn down/rebuilt on routine per-frame ViewModel
        // notifications.
        Positioned.fill(
          child: LayoutBuilder(
            builder: (context, constraints) {
              vm.setSurfaceSize(constraints.biggest);
              return Listener(
                key: placementGestureDetectorKey,
                behavior: HitTestBehavior.translucent,
                onPointerDown: _onPointerDown,
                onPointerMove: _onPointerMove,
                onPointerUp: _onPointerUp,
                onPointerCancel: _onPointerCancel,
                child: ArCorePlatformView(mode: vm.nativeMode),
              );
            },
          ),
        ),

        // Top chrome: back + product name + honest guidance. This is the
        // ONLY part that still rebuilds on every ViewModel notification —
        // deliberately scoped away from the AndroidView above.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.s,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _RoundIconButton(
                        icon: Icons.arrow_back_ios_new,
                        onPressed: () => Navigator.of(context).maybePop(),
                      ),
                      const SizedBox(width: AppSpacing.s),
                      Expanded(
                        child: Text(
                          vm.productTitle,
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
                  const SizedBox(height: AppSpacing.s),
                  Consumer<RoomArCoreViewModel>(
                    builder: (context, vm, _) =>
                        _GuidanceBanner(message: vm.guidanceMessage),
                  ),
                  Consumer<RoomArCoreViewModel>(
                    builder: (context, vm, _) => vm.flash == null
                        ? const SizedBox.shrink()
                        : Padding(
                            padding: const EdgeInsets.only(top: AppSpacing.xs),
                            child: _FlashBanner(message: vm.flash!),
                          ),
                  ),
                ],
              ),
            ),
          ),
        ),

        // Bottom chrome: placement controls + the always-available
        // fallback to the no-camera 3D preview.
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.m),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Consumer<RoomArCoreViewModel>(
                    builder: (context, vm, _) => vm.hasAnchor
                        ? Padding(
                            padding: const EdgeInsets.only(
                              bottom: AppSpacing.xs,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: OutlinedButton.icon(
                                onPressed: vm.resetPlacement,
                                icon: const Icon(
                                  Icons.restart_alt,
                                  color: AppColors.white,
                                ),
                                label: const Text(
                                  'Remove / reset placement',
                                  style: TextStyle(color: AppColors.white),
                                ),
                                style: OutlinedButton.styleFrom(
                                  side: const BorderSide(
                                    color: AppColors.white,
                                  ),
                                ),
                              ),
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  TextButton(
                    onPressed: () => Navigator.of(context).pushReplacementNamed(
                      RouteNames.roomArPreview,
                      arguments: vm.fallbackPreviewArgs,
                    ),
                    child: Text(
                      'Prefer a 3D preview instead?',
                      style: AppTypography.label.copyWith(
                        color: AppColors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// The ARCore camera/plane/model PlatformView.
///
/// Round 6 correction (tracker §29): round 5 (§27) forced this onto
/// Android's classic ("expensive") **Hybrid Composition** path — Google's
/// own documented fallback for "a platform view renders correctly but never
/// receives touch input", which is exactly what round 4's evidence showed.
/// The very next physical test showed a **new, worse** regression instead:
/// single-finger taps stopped reaching Flutter's gesture arena at all
/// (`gStart` stayed 0 through repeated taps), and only several rapid
/// two-finger touches eventually got through. The round *before* Hybrid
/// Composition (plain `AndroidView`, i.e. Flutter's default Texture-Layer
/// Hybrid Composition) had reliably delivered single-finger taps across five
/// separate physical test runs on real hardware. The only variable Hybrid
/// Composition changed was gesture delivery itself, and it made that worse,
/// not better — so it's reverted here, back to the configuration already
/// proven live on real hardware.
class ArCorePlatformView extends StatelessWidget {
  final String mode;
  const ArCorePlatformView({super.key, required this.mode});

  @override
  Widget build(BuildContext context) {
    final vm = context.read<RoomArCoreViewModel>();
    return AndroidView(
      viewType: RoomArCoreChannel.viewType,
      // `mode` as a creation param (not a post-creation `setObject`
      // channel call) — the channel call races the PlatformView's own
      // creation and gets silently dropped, leaving the renderer showing
      // nothing at all. See RoomArCoreViewFactory.kt.
      creationParams: <String, dynamic>{'mode': mode},
      creationParamsCodec: const StandardMessageCodec(),
      // Guaranteed-post-creation re-send, once Flutter confirms the
      // platform view genuinely exists — closes the same race for a
      // Storage-delivered external model (which can only ever be set
      // after construction, once the download/cache resolve finishes).
      // See RoomArCoreViewModel.onPlatformViewReady's doc comment.
      onPlatformViewCreated: (_) => vm.onPlatformViewReady(),
    );
  }
}

class _GuidanceBanner extends StatelessWidget {
  final String message;
  const _GuidanceBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: AppTypography.bodySmall.copyWith(color: AppColors.white),
      ),
    );
  }
}

class _FlashBanner extends StatelessWidget {
  final String message;
  const _FlashBanner({required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        message,
        style: AppTypography.bodySmall.copyWith(color: AppColors.white),
      ),
    );
  }
}

class _RoundIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  const _RoundIconButton({required this.icon, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.4),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: AppColors.white, size: 20),
        onPressed: onPressed,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────

class _PermissionRequest extends StatelessWidget {
  final PermissionStatus status;
  final VoidCallback onRequest;
  final Future<bool> Function() onOpenSettings;
  final VoidCallback onRecheck;
  final VoidCallback onViewPreview;

  const _PermissionRequest({
    required this.status,
    required this.onRequest,
    required this.onOpenSettings,
    required this.onRecheck,
    required this.onViewPreview,
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
              'Room AR uses the rear camera to detect real surfaces in your '
              'room and place the piece there. Nothing is recorded or '
              'uploaded.',
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

class _EngineUnavailable extends StatelessWidget {
  final String? message;
  final VoidCallback onViewPreview;

  const _EngineUnavailable({this.message, required this.onViewPreview});

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
                'AR isn\'t available right now',
                style: AppTypography.headingMedium.copyWith(
                  color: AppColors.white,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                message ??
                    'This device can\'t run the camera AR experience for this '
                        'product right now.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.white.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
              const SizedBox(height: AppSpacing.l),
              AppPrimaryButton(
                label: 'View a 3D preview instead',
                onPressed: onViewPreview,
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}

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
                'Please check your connection and try again shortly.',
                style: AppTypography.bodyMedium.copyWith(
                  color: AppColors.white.withValues(alpha: 0.8),
                  height: 1.4,
                ),
              ),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
