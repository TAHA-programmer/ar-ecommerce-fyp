import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

/// "Position Yourself" guidance card (Phase 9.3 Stage 5) — one consistent
/// layout; [isFemaleModel] only selects which illustration matches the
/// product's configured [ProductVtoModelType], never a different design.
class VtoPositioningSection extends StatelessWidget {
  final bool isFemaleModel;

  const VtoPositioningSection({super.key, required this.isFemaleModel});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.accessibility, color: AppColors.primaryDark),
            const SizedBox(width: 8),
            Text(
              'Position Yourself',
              style: AppTypography.bodyLarge.copyWith(
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                flex: 2,
                child: Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F5F5),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.asset(
                      isFemaleModel
                          ? AppAssets.vtoPositioningFemale
                          : AppAssets.vtoPositioningMale,
                      fit: BoxFit.cover,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                flex: 3,
                child: Column(
                  children: const [
                    _InstructionRow(
                      icon: Icons.directions_walk,
                      title: 'Full body in frame',
                      subtitle: 'Head to feet, standing, facing the camera.',
                    ),
                    SizedBox(height: 8),
                    _InstructionRow(
                      icon: Icons.crop_free,
                      title: 'Plain background',
                      subtitle: 'A clear wall works best — avoid clutter.',
                    ),
                    SizedBox(height: 8),
                    _InstructionRow(
                      icon: Icons.light_mode_outlined,
                      title: 'Even, front-facing light',
                      subtitle: 'Avoid strong backlight or deep shadow.',
                    ),
                    SizedBox(height: 8),
                    _InstructionRow(
                      icon: Icons.accessibility_new,
                      title: 'Arms slightly away from your sides',
                      subtitle: 'One person only, form-revealing clothing.',
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _InstructionRow extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _InstructionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutralLight),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8E8),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryDark, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: AppTypography.bodySmall.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.primaryDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(subtitle, style: AppTypography.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
