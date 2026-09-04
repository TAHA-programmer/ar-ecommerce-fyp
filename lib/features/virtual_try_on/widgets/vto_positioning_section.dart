import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class VtoPositioningSection extends StatelessWidget {
  final bool isFemaleVariant;

  const VtoPositioningSection({super.key, required this.isFemaleVariant});

  @override
  Widget build(BuildContext context) {
    if (isFemaleVariant) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  flex: 2,
                  child: Container(
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFF5F5F5,
                      ), // Add background for female too since they want it like male
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        AppAssets.vtoPositioningFemale,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _buildFemaleInstructionRow(
                        Icons.directions_walk,
                        'Stand inside the\nbody outline',
                      ),
                      _buildFemaleDivider(),
                      _buildFemaleInstructionRow(
                        Icons.accessibility_new,
                        'Keep the whole\nbody visible',
                      ),
                      _buildFemaleDivider(),
                      _buildFemaleInstructionRow(
                        Icons.light_mode_outlined,
                        'Use sufficient\nlighting',
                      ),
                      _buildFemaleDivider(),
                      _buildFemaleInstructionRow(
                        Icons.compare_arrows,
                        'Move farther from\nthe camera when requested',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
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
                      color: const Color(0xFFF5F5F5), // Pale grey
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.asset(
                        AppAssets.vtoPositioningMale,
                        fit: BoxFit.cover,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      _buildMaleInstructionRow(
                        Icons.directions_walk,
                        'Stand inside the body outline',
                        'Align yourself within the guide.',
                      ),
                      _buildMaleDivider(),
                      _buildMaleInstructionRow(
                        Icons.accessibility_new,
                        'Keep the whole body visible',
                        'From head to feet for best results.',
                      ),
                      _buildMaleDivider(),
                      _buildMaleInstructionRow(
                        Icons.light_mode_outlined,
                        'Use sufficient lighting',
                        'Avoid backlight and dim places.',
                      ),
                      _buildMaleDivider(),
                      _buildMaleInstructionRow(
                        Icons.compare_arrows,
                        'Move farther when requested',
                        'Follow on-screen prompts.',
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

  Widget _buildMaleInstructionRow(
    IconData icon,
    String title,
    String subtitle,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
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
              color: Color(0xFFF6F8E8), // pale lime
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

  Widget _buildMaleDivider() {
    return const SizedBox.shrink(); // Replaced by container margins
  }

  Widget _buildFemaleInstructionRow(IconData icon, String title) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.neutralLight),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
              color: Color(0xFFF6F8E8), // pale lime
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.primaryDark, size: 16),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: AppTypography.bodySmall.copyWith(
                color: AppColors.primaryDark,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFemaleDivider() {
    return const SizedBox.shrink(); // Replaced by container margins
  }
}
