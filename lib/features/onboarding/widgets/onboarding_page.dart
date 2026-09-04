import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';

class OnboardingPage extends StatelessWidget {
  final Widget visual;
  final String title;
  final String description;

  const OnboardingPage({
    super.key,
    required this.visual,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    // Calculate responsive scale based on 430px Figma baseline
    final screenWidth = MediaQuery.of(context).size.width;
    final widthScale = screenWidth / 430.0;

    final headingSize = (36 * widthScale).clamp(28.0, 36.0);
    final bodySize = (20 * widthScale).clamp(16.0, 20.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
      child: Column(
        children: [
          // Allow visual to take whatever space is left by text
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.m),
              child: Align(alignment: Alignment.center, child: visual),
            ),
          ),
          // Ensure container width doesn't squeeze text unnecessarily
          SizedBox(
            width: double.infinity,
            child: Column(
              children: [
                Text(
                  title,
                  style: AppTypography.displayMedium.copyWith(
                    fontSize: headingSize,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.m),
                Text(
                  description,
                  style: GoogleFonts.inter(
                    fontSize: bodySize,
                    fontWeight: FontWeight.w300,
                    color: AppColors.textPrimary,
                    height: 1.4,
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
