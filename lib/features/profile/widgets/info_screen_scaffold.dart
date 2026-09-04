import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../auth/widgets/auth_header.dart';

class InfoSectionData {
  final int? number;
  final String title;
  final String body;

  const InfoSectionData({this.number, required this.title, required this.body});
}

class InfoScreenScaffold extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<InfoSectionData> sections;
  final Widget? contactSection;

  const InfoScreenScaffold({
    super.key,
    required this.title,
    required this.subtitle,
    required this.sections,
    this.contactSection,
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
                    SizedBox(height: 32 * scale),
                    ...sections.map(
                      (section) => _buildInfoCard(section, scale),
                    ),
                    if (contactSection != null) ...[
                      SizedBox(height: 24 * scale),
                      contactSection!,
                    ],
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

  Widget _buildInfoCard(InfoSectionData section, double scale) {
    return Container(
      margin: EdgeInsets.only(bottom: 24 * scale),
      padding: EdgeInsets.all(20 * scale),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.2),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (section.number != null) ...[
            Container(
              width: 32 * scale,
              height: 32 * scale,
              decoration: const BoxDecoration(
                color: AppColors.primary,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Text(
                '${section.number}',
                style: AppTypography.title.copyWith(
                  color: AppColors.white,
                  fontSize: 16 * scale,
                ),
              ),
            ),
            SizedBox(width: 16 * scale),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (section.number == null) SizedBox(height: 4 * scale),
                Text(
                  section.title,
                  style: AppTypography.title.copyWith(
                    fontSize: 18 * scale,
                    color: AppColors.textPrimary,
                  ),
                ),
                SizedBox(height: 8 * scale),
                Text(
                  section.body,
                  style: AppTypography.bodyLarge.copyWith(
                    color: AppColors.textSecondary,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
