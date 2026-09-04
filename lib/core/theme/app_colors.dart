import 'package:flutter/material.dart';

class AppColors {
  AppColors._();

  // Primary brand colors
  static const Color primary = Color(0xFFAEC500); // Lime
  static const Color primaryDark = Color(0xFF768900); // Darker Lime
  static const Color primaryDarker = Color(
    0xFF92A700,
  ); // Between Lime and Dark Lime
  static const Color primaryLight = Color(0xFFC5DA20); // Brighter Lime

  // Neutrals
  static const Color white = Color(0xFFFFFFFF);
  static const Color black = Color(0xFF000000);

  static const Color neutralLight = Color(0xFFE4E0E4);
  static const Color neutralMediumLight = Color(0xFFCECACF);
  static const Color neutralMedium = Color(0xFFADA9AD);
  static const Color neutralDark = Color(0xFF8E898E);

  // Backgrounds
  static const Color background = white;
  static const Color surface = white;

  // Text
  static const Color textPrimary = black;
  static const Color textSecondary = neutralDark;

  // Semantic Feedback Colors (Not core branding, for UI feedback only)
  static const Color success = Color(0xFF4CAF50);
  static const Color error = Color(0xFFF44336);
  static const Color warning = Color(0xFFFF9800);
  static const Color info = Color(0xFF2196F3);
}
