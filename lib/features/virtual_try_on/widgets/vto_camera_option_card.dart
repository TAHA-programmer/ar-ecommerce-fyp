import 'package:flutter/material.dart';
import '../models/virtual_try_on_camera_type.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';

class VtoCameraOptionCard extends StatelessWidget {
  final VirtualTryOnCameraType type;
  final bool isSelected;
  final VoidCallback onTap;
  final bool isFemaleVariant;

  const VtoCameraOptionCard({
    super.key,
    required this.type,
    required this.isSelected,
    required this.onTap,
    required this.isFemaleVariant,
  });

  @override
  Widget build(BuildContext context) {
    final isFront = type == VirtualTryOnCameraType.front;
    final title = isFront ? 'Front Camera' : 'Rear Camera';
    final icon = isFront
        ? Icons.person
        : Icons.camera_rear; // Approximate icons

    final Color bgColor = isSelected
        ? const Color(0xFFF6F8E8)
        : AppColors.white; // Pale lime
    final Color borderColor = isSelected
        ? AppColors.primary
        : AppColors.neutralLight;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: isFemaleVariant && !isSelected
              ? AppColors.white
              : bgColor, // Female has white selected bg?
          // Wait, male has pale green bg when selected. Female has white bg but lime border.
          // The Figma states: male selected has pale lime background. Female selected has white background, lime border.
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: borderColor, width: 1.5),
        ),
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Row(
              children: [
                Icon(icon, size: 28, color: AppColors.textPrimary),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        style: AppTypography.bodySmall.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (isSelected)
              Positioned(
                right: -6,
                top: -6,
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: const BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.check,
                    size: 12,
                    color: AppColors.white,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
