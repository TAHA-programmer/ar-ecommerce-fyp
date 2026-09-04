import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';

class RoomArInfoCard extends StatelessWidget {
  const RoomArInfoCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: AppColors
            .surface, // Figma shows a pale background, we can use a slight tint or just white with border. Target looks slightly tinted, let's use a very pale lime or just surface with a border. Actually, looking closely, the background is a very pale yellowish/green tint.
        // Let's use primary with very low opacity to simulate the pale tint.
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.15)),
      ),
      child: Material(
        color: AppColors.primary.withValues(
          alpha: 0.03,
        ), // Pale tint background
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            children: [
              _buildInfoRow(
                icon: Icons.camera_alt_outlined,
                text:
                    'Camera access is required to\nplace products in your room.',
              ),
              Divider(
                color: AppColors.primary.withValues(alpha: 0.15),
                height: 1,
                thickness: 1,
                indent: 16,
                endIndent: 16,
              ),
              _buildInfoRow(
                icon: Icons.smartphone_outlined,
                text:
                    'AR is available only on supported\ndevices and when a valid 3D model exists.',
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow({required IconData icon, required String text}) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primary, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.textPrimary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
