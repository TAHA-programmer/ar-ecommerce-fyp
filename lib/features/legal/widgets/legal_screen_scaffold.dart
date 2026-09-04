import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_typography.dart';
import '../../auth/widgets/auth_header.dart';
import 'legal_section_card.dart';

class LegalSectionData {
  final int number;
  final String title;
  final String body;

  const LegalSectionData({
    required this.number,
    required this.title,
    required this.body,
  });
}

class LegalScreenScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final String lastUpdated;
  final List<LegalSectionData> sections;

  const LegalScreenScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.lastUpdated,
    required this.sections,
  });

  @override
  Widget build(BuildContext context) {
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.dark,
      ),
    );

    final double width = MediaQuery.of(context).size.width;
    final double scale = (width / 430.0).clamp(0.8, 1.2);
    final double headerHeight = 220 * scale;

    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Stack(
              children: [
                AuthHeader(height: headerHeight),
                Positioned(
                  top: MediaQuery.of(context).padding.top + 8,
                  left: 16,
                  child: IconButton(
                    icon: const Icon(
                      Icons.arrow_back_ios,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: () {
                      if (Navigator.canPop(context)) {
                        Navigator.pop(context);
                      }
                    },
                  ),
                ),
              ],
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: EdgeInsets.symmetric(horizontal: 24.0 * scale),
                child: Column(
                  children: [
                    SizedBox(height: 16 * scale),
                    Text(
                      title,
                      style: const TextStyle(
                        fontFamily: 'Playfair Display',
                        fontSize: 28,
                        fontWeight: FontWeight.w700,
                        color: AppColors.textPrimary,
                        letterSpacing: 0.5,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 12 * scale),
                    Text(
                      subtitle,
                      style: AppTypography.bodyLarge.copyWith(
                        color: AppColors.textSecondary,
                        fontWeight: FontWeight.w400,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 12 * scale),
                    Text(
                      lastUpdated,
                      style: AppTypography.bodyMedium.copyWith(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    SizedBox(height: 32 * scale),
                    ...sections.map(
                      (section) => LegalSectionCard(
                        number: section.number,
                        title: section.title,
                        body: section.body,
                      ),
                    ),
                    SizedBox(height: 48 * scale),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
