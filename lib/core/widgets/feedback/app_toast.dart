import 'package:flutter/material.dart';
import 'dart:async';
import '../../theme/app_colors.dart';
import '../../theme/app_radii.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class AppToast {
  AppToast._();

  static OverlayEntry? _currentEntry;
  static Timer? _currentTimer;
  static _ToastWidgetState? _currentState;

  static void _show(
    BuildContext? context,
    String message,
    Color accentColor,
    IconData icon, {
    String? title,
    VoidCallback? onTap,
    OverlayState? overlay,
  }) {
    // If there is a toast currently showing, animate it out quickly before showing new one
    if (_currentEntry != null && _currentState != null) {
      _currentState!.dismiss();
      _currentEntry = null;
      _currentState = null;
    }
    _currentTimer?.cancel();

    // `overlay` is given when there is no BuildContext BELOW an Overlay (the
    // FCM foreground banner fires from a stream with only the root Navigator's
    // OverlayState in hand - `Overlay.of(overlayState.context)` would look for
    // an ancestor Overlay and throw "No Overlay widget found").
    final overlayState = overlay ?? Overlay.of(context!);

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) {
        return _ToastWidget(
          message: message,
          title: title,
          onTap: onTap,
          accentColor: accentColor,
          icon: icon,
          onStateCreated: (state) {
            _currentState = state;
          },
          onDismissed: () {
            if (entry.mounted) {
              entry.remove();
            }
            if (_currentEntry == entry) {
              _currentEntry = null;
              _currentState = null;
            }
          },
        );
      },
    );

    _currentEntry = entry;
    overlayState.insert(entry);

    _currentTimer = Timer(Duration(seconds: onTap == null ? 3 : 5), () {
      if (_currentEntry == entry && _currentState != null) {
        _currentState!.dismiss();
      }
    });
  }

  static void success(BuildContext context, String message) {
    _show(context, message, AppColors.success, Icons.check_circle_outline);
  }

  static void error(BuildContext context, String message) {
    _show(context, message, AppColors.error, Icons.error_outline);
  }

  static void warning(BuildContext context, String message) {
    _show(context, message, AppColors.warning, Icons.warning_amber_rounded);
  }

  static void info(BuildContext context, String message) {
    _show(context, message, AppColors.primary, Icons.info_outline);
  }

  /// A tappable push-notification banner (FCM Stage S5): bold [title] over
  /// [message], dismissed on tap after calling [onTap]. Stays a little longer
  /// than the 3 s status toasts so it can actually be tapped.
  static void notification(
    BuildContext? context, {
    OverlayState? overlay,
    required String title,
    required String message,
    required VoidCallback onTap,
  }) {
    assert(
      context != null || overlay != null,
      'AppToast.notification needs a context or an OverlayState',
    );
    _show(
      context,
      message,
      AppColors.primary,
      Icons.notifications_active_outlined,
      title: title,
      onTap: onTap,
      overlay: overlay,
    );
  }
}

class _ToastWidget extends StatefulWidget {
  final String message;
  final String? title;
  final VoidCallback? onTap;
  final Color accentColor;
  final IconData icon;
  final VoidCallback onDismissed;
  final void Function(_ToastWidgetState) onStateCreated;

  const _ToastWidget({
    required this.message,
    this.title,
    this.onTap,
    required this.accentColor,
    required this.icon,
    required this.onDismissed,
    required this.onStateCreated,
  });

  @override
  State<_ToastWidget> createState() => _ToastWidgetState();
}

class _ToastWidgetState extends State<_ToastWidget>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<Offset> _slideAnimation;
  late Animation<double> _fadeAnimation;
  bool _isDismissing = false;

  @override
  void initState() {
    super.initState();
    widget.onStateCreated(this);
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    );

    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -0.5),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));

    _fadeAnimation = Tween<double>(
      begin: 0.0,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeIn));

    _controller.forward();
  }

  void dismiss() {
    if (_isDismissing) return;
    _isDismissing = true;
    _controller.reverse().then((_) {
      if (mounted) {
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: MediaQuery.of(context).padding.top + 16,
      left: 16,
      right: 16,
      child: Material(
        color: Colors.transparent,
        child: SlideTransition(
          position: _slideAnimation,
          child: FadeTransition(
            opacity: _fadeAnimation,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: widget.onTap == null
                  ? null
                  : () {
                      widget.onTap!();
                      dismiss();
                    },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.m,
                  vertical: AppSpacing.m,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E1E), // Dark charcoal
                  borderRadius: AppRadii.mediumBorder,
                  boxShadow: AppShadows.medium,
                  border: Border.all(
                    color: widget.accentColor.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(widget.icon, color: widget.accentColor, size: 24),
                    const SizedBox(width: AppSpacing.s),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (widget.title != null)
                            Text(
                              widget.title!,
                              style: AppTypography.bodyMedium.copyWith(
                                color: Colors.white,
                                fontFamily: 'Inter',
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          if (widget.message.isNotEmpty)
                            Text(
                              widget.message,
                              style: AppTypography.bodyMedium.copyWith(
                                color: Colors.white,
                                fontFamily: 'Inter',
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
