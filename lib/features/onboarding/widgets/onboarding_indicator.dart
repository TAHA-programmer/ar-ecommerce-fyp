import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';

class OnboardingIndicator extends StatelessWidget {
  final int totalPages;
  final int currentPage;

  const OnboardingIndicator({
    super.key,
    required this.totalPages,
    required this.currentPage,
  });

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final scale = (screenWidth / 430.0).clamp(0.8, 1.2);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(totalPages, (index) {
        final isActive = index == currentPage;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          margin: EdgeInsets.symmetric(horizontal: 4.0 * scale),
          height: 8.0 * scale,
          width: (isActive ? 24.0 : 8.0) * scale,
          decoration: BoxDecoration(
            color: isActive ? AppColors.primary : AppColors.neutralMediumLight,
            borderRadius: BorderRadius.circular(4.0 * scale),
          ),
        );
      }),
    );
  }
}
