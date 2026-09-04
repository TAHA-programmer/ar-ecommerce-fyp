import 'package:flutter/material.dart';
import 'app_colors.dart';

class AppShadows {
  AppShadows._();

  static final List<BoxShadow> subtle = [
    BoxShadow(
      color: AppColors.black.withValues(alpha: 0.05),
      offset: const Offset(0, 2),
      blurRadius: 8,
      spreadRadius: 0,
    ),
  ];

  static final List<BoxShadow> medium = [
    BoxShadow(
      color: AppColors.black.withValues(alpha: 0.1),
      offset: const Offset(0, 4),
      blurRadius: 16,
      spreadRadius: 0,
    ),
  ];
}
