import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../models/marker_calibration.dart';
import '../viewmodels/marker_ar_viewmodel.dart';

/// Marker-size + scale-trim calibration (`SCALE_CONTRACT.md` §3). Presented as a
/// standard TWin AR bottom sheet on a white surface with lime accents — nothing
/// PoC/debug about it.
class MarkerArCalibrationSheet extends StatefulWidget {
  final MarkerArViewModel viewModel;

  const MarkerArCalibrationSheet({super.key, required this.viewModel});

  static Future<void> show(BuildContext context, MarkerArViewModel viewModel) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: AppColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: AppRadii.large),
      ),
      builder: (_) => MarkerArCalibrationSheet(viewModel: viewModel),
    );
  }

  @override
  State<MarkerArCalibrationSheet> createState() =>
      _MarkerArCalibrationSheetState();
}

class _MarkerArCalibrationSheetState extends State<MarkerArCalibrationSheet> {
  late double _markerMm;
  late double _trim;
  late bool _confirmed;

  @override
  void initState() {
    super.initState();
    final c = widget.viewModel.calibration;
    _markerMm = c.markerSizeMm;
    _trim = c.scaleTrim;
    _confirmed = c.confirmed;
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        AppSpacing.l,
        AppSpacing.l,
        AppSpacing.l,
        AppSpacing.l + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Marker size & scale', style: AppTypography.headingMedium),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'The pose solver assumes the printed outer black square is exactly '
            'this many millimetres. Measure your printed marker and enter it so '
            'the piece renders at true real-world size.',
            style: AppTypography.bodySmall.copyWith(height: 1.4),
          ),
          const SizedBox(height: AppSpacing.m),
          _SliderRow(
            label: 'Marker',
            valueLabel: '${_markerMm.toStringAsFixed(0)} mm',
            value: _markerMm,
            min: MarkerCalibration.minMarkerMm,
            max: MarkerCalibration.maxMarkerMm,
            divisions:
                (MarkerCalibration.maxMarkerMm - MarkerCalibration.minMarkerMm)
                    .round(),
            onChanged: (v) {
              setState(() => _markerMm = v);
              widget.viewModel.setMarkerSizeMm(v);
            },
          ),
          _SliderRow(
            label: 'Scale trim',
            valueLabel: '${_trim.toStringAsFixed(2)}×',
            value: _trim,
            min: MarkerCalibration.minScaleTrim,
            max: MarkerCalibration.maxScaleTrim,
            divisions: 150,
            onChanged: (v) {
              setState(() => _trim = v);
              widget.viewModel.setScaleTrim(v);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            dense: true,
            controlAffinity: ListTileControlAffinity.leading,
            value: _confirmed,
            activeColor: AppColors.primary,
            title: Text(
              'I physically measured this marker — treat the scale as calibrated',
              style: AppTypography.bodySmall,
            ),
            onChanged: (v) {
              setState(() => _confirmed = v ?? false);
              widget.viewModel.setCalibrationConfirmed(_confirmed);
            },
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton(
                    onPressed: () async {
                      await widget.viewModel.resetCalibration();
                      if (!context.mounted) return;
                      final c = widget.viewModel.calibration;
                      setState(() {
                        _markerMm = c.markerSizeMm;
                        _trim = c.scaleTrim;
                        _confirmed = c.confirmed;
                      });
                    },
                    child: Text(
                      'Reset defaults',
                      style: AppTypography.label.copyWith(
                        color: AppColors.primaryDark,
                      ),
                    ),
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: Text(
                  'Done',
                  style: AppTypography.label.copyWith(
                    color: AppColors.primaryDark,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        SizedBox(
          width: 78,
          child: Text(label, style: AppTypography.bodyMedium),
        ),
        Expanded(
          child: Slider(
            value: value.clamp(min, max),
            min: min,
            max: max,
            divisions: divisions,
            activeColor: AppColors.primary,
            label: valueLabel,
            onChanged: onChanged,
          ),
        ),
        SizedBox(
          width: 62,
          child: Text(
            valueLabel,
            textAlign: TextAlign.end,
            style: AppTypography.bodyMedium,
          ),
        ),
      ],
    );
  }
}
