import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../models/marker_ar_config.dart';
import '../models/marker_ar_frame.dart';
import '../models/marker_ar_object.dart';
import '../models/marker_calibration.dart';

/// Development-only metrics HUD (fps / detection time / intrinsics / pose /
/// calibration). Never shown in a release build and never a customer-facing
/// control — gated by `MarkerArViewModel.debugHudVisible` which is itself
/// `kDebugMode`-guarded.
class MarkerArDebugOverlay extends StatelessWidget {
  final MarkerArFrame frame;
  final MarkerArConfig config;
  final MarkerCalibration calibration;
  final MarkerArObject object;
  final double offX;
  final double offZ;
  final double yaw;
  final bool placed;

  const MarkerArDebugOverlay({
    super.key,
    required this.frame,
    required this.config,
    required this.calibration,
    required this.object,
    required this.offX,
    required this.offZ,
    required this.yaw,
    required this.placed,
  });

  @override
  Widget build(BuildContext context) {
    final k = frame.k;
    final dims = config.dimsFor(object);
    final lines = <String>[
      'DEBUG · fps ${frame.fps.toStringAsFixed(1)}  det ${frame.detMs.toStringAsFixed(0)} ms  pass ${frame.pass}',
      'track ${frame.track.name}'
          '${frame.track == MarkerTrackState.holding ? "  held ${(frame.heldMs / 1000).toStringAsFixed(1)}s" : ""}',
      'analysis ${frame.imgW}x${frame.imgH}  focal ${frame.focalMm.toStringAsFixed(2)} mm',
      'fx ${k[0].toStringAsFixed(0)}  fy ${k[1].toStringAsFixed(0)}  cx ${k[2].toStringAsFixed(0)}  cy ${k[3].toStringAsFixed(0)}',
      'marker dist ${(frame.distM ?? 0).toStringAsFixed(2)} m  side ${frame.markerSidePx.toStringAsFixed(0)} px',
      'placement ${placed ? "set" : "default"}  off ${offX.toStringAsFixed(2)},${offZ.toStringAsFixed(2)} m  yaw ${(yaw * 57.2958).toStringAsFixed(0)}°',
      'obj ${object.name}  ${(dims[0] * 100).toStringAsFixed(0)}x${(dims[2] * 100).toStringAsFixed(0)}x${(dims[1] * 100).toStringAsFixed(0)} cm',
      'OpenCV ${config.openCvVersion}  ${config.dict} id ${config.markerId}',
      'marker ${calibration.markerSizeMm.toStringAsFixed(0)} mm  trim ${calibration.scaleTrim.toStringAsFixed(2)}x  ${calibration.confirmed ? "CALIBRATED" : "approx"}',
    ];
    return Container(
      padding: const EdgeInsets.all(AppSpacing.xs),
      decoration: BoxDecoration(
        color: AppColors.black.withValues(alpha: 0.45),
        borderRadius: AppRadii.smallBorder,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final l in lines)
            Text(
              l,
              style: const TextStyle(
                color: AppColors.white,
                fontFamily: 'monospace',
                fontSize: 10,
                height: 1.35,
              ),
            ),
        ],
      ),
    );
  }
}
