import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

/// Bottom control cluster for the Marker-AR screen: object selector slot,
/// rotate slider, Face Me / Reset, and the marker-sheet + calibration actions.
/// Dark translucent panel so it reads over the camera while keeping TWin AR
/// type + lime accents.
class MarkerArControls extends StatelessWidget {
  final Widget selector;
  final double yaw;
  final ValueChanged<double> onYaw;
  final VoidCallback onFaceMe;
  final VoidCallback onReset;
  final VoidCallback onOpenMarkerSheet;
  final VoidCallback onOpenCalibration;
  final bool calibrated;

  const MarkerArControls({
    super.key,
    required this.selector,
    required this.yaw,
    required this.onYaw,
    required this.onFaceMe,
    required this.onReset,
    required this.onOpenMarkerSheet,
    required this.onOpenCalibration,
    required this.calibrated,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.55),
        borderRadius: const BorderRadius.vertical(top: AppRadii.large),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        AppSpacing.s,
        AppSpacing.m,
        AppSpacing.xs,
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Expanded(child: selector),
                const SizedBox(width: AppSpacing.xs),
                _IconAction(
                  icon: Icons.straighten,
                  tooltip: 'Marker size / scale',
                  highlighted: !calibrated,
                  onTap: onOpenCalibration,
                ),
                _IconAction(
                  icon: Icons.print_outlined,
                  tooltip: 'Marker sheet (A4)',
                  onTap: onOpenMarkerSheet,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xxs),
            Row(
              children: [
                Text(
                  'Rotate',
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.white,
                  ),
                ),
                Expanded(
                  child: Slider(
                    value: yaw.clamp(-math.pi, math.pi),
                    min: -math.pi,
                    max: math.pi,
                    activeColor: AppColors.primary,
                    onChanged: onYaw,
                  ),
                ),
                TextButton(
                  onPressed: onFaceMe,
                  child: Text(
                    'Face me',
                    style: AppTypography.label.copyWith(
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
                TextButton(
                  onPressed: onReset,
                  child: Text(
                    'Reset',
                    style: AppTypography.label.copyWith(
                      color: AppColors.primaryLight,
                    ),
                  ),
                ),
              ],
            ),
            Text(
              'Tap the floor to place · drag to move · two-finger twist to '
              'rotate · Reset recentres & faces you',
              style: AppTypography.caption.copyWith(
                color: AppColors.white.withValues(alpha: 0.7),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _IconAction extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;
  final bool highlighted;

  const _IconAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.highlighted = false,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onTap,
      tooltip: tooltip,
      icon: Icon(
        icon,
        color: highlighted ? AppColors.primaryLight : AppColors.white,
      ),
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
    );
  }
}
