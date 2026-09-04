import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../models/marker_ar_frame.dart';

/// Honest Searching / Tracking / Holding / Too Far chrome for the Marker-AR
/// camera screen — a top explainer strip plus a centred status pill. Styled with
/// the TWin AR tokens (Inter type, lime "active" accent) but on dark scrims so it
/// stays legible over the live camera.
class MarkerArStatusBanner extends StatelessWidget {
  final MarkerTrackState track;
  final double heldMs;
  final double markerSidePx;
  final bool calibrated;
  final double markerMm;
  final String objectName;
  final bool engineError;
  final String? engineErrorMessage;

  const MarkerArStatusBanner({
    super.key,
    required this.track,
    required this.heldMs,
    required this.markerSidePx,
    required this.calibrated,
    required this.markerMm,
    required this.objectName,
    this.engineError = false,
    this.engineErrorMessage,
  });

  String get _bannerText {
    if (engineError) {
      return engineErrorMessage ??
          'Room AR is not available on this device right now.';
    }
    switch (track) {
      case MarkerTrackState.tooFar:
        return 'Marker too far or too small (${markerSidePx.toStringAsFixed(0)} px). '
            'Move closer, or print a larger marker. Not tracking yet.';
      case MarkerTrackState.holding:
        return 'Holding the last position — the marker is not visible right now '
            '(${(heldMs / 1000).toStringAsFixed(1)} s). This is a frozen preview, '
            'not live tracking.';
      case MarkerTrackState.searching:
        return 'Point the rear camera at the printed marker. This device has no '
            'motion sensors, so the piece only appears where the marker is.';
      case MarkerTrackState.tracking:
        return 'The $objectName is anchored to the printed marker. '
            '${calibrated ? "Scale calibrated to ${markerMm.toStringAsFixed(0)} mm." : "Size is approximate — tap the ruler to calibrate."}';
    }
  }

  ({String label, Color color, IconData icon}) get _pill {
    if (engineError) {
      return (
        label: 'AR unavailable',
        color: AppColors.error,
        icon: Icons.error_outline,
      );
    }
    switch (track) {
      case MarkerTrackState.tracking:
        return (
          label: 'Tracking',
          color: AppColors.primaryDark,
          icon: Icons.check_circle,
        );
      case MarkerTrackState.holding:
        return (
          label: 'Holding — ${(heldMs / 1000).toStringAsFixed(1)} s',
          color: AppColors.warning,
          icon: Icons.pause_circle_outline,
        );
      case MarkerTrackState.tooFar:
        return (
          label: 'Marker too far',
          color: AppColors.warning,
          icon: Icons.zoom_out_map,
        );
      case MarkerTrackState.searching:
        return (
          label: 'Searching for marker',
          color: AppColors.neutralDark,
          icon: Icons.search,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final pill = _pill;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          color: AppColors.black.withValues(alpha: 0.55),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
          ),
          child: SafeArea(
            bottom: false,
            child: Text(
              _bannerText,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.white,
                height: 1.35,
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        Container(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.m,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            color: pill.color.withValues(alpha: 0.92),
            borderRadius: AppRadii.pillBorder,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(pill.icon, size: 16, color: AppColors.white),
              const SizedBox(width: AppSpacing.xs),
              Text(
                pill.label,
                style: AppTypography.label.copyWith(color: AppColors.white),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
