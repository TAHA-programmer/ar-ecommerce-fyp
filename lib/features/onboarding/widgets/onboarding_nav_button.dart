import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class OnboardingNavButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onPressed;
  final bool isVisible;

  const OnboardingNavButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.isVisible = true,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 430.0).clamp(0.8, 1.2);
    final buttonSize = 56.0 * scale;

    return AnimatedOpacity(
      duration: const Duration(milliseconds: 200),
      opacity: isVisible ? 1.0 : 0.0,
      child: IgnorePointer(
        ignoring: !isVisible,
        child: InkWell(
          onTap: onPressed,
          customBorder: const CircleBorder(),
          child: Container(
            width: buttonSize,
            height: buttonSize,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: AppColors.white, size: 28 * scale),
          ),
        ),
      ),
    );
  }
}
