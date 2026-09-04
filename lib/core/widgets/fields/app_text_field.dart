import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radii.dart';
import '../../theme/app_shadows.dart';
import '../../theme/app_typography.dart';
import '../../theme/app_spacing.dart';

class AppTextField extends StatelessWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final TextInputType keyboardType;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final String? Function(String?)? validator;
  final bool enabled;
  final bool obscureText;
  final TextInputAction? textInputAction;
  final void Function(String)? onChanged;
  final String? errorText;

  /// Optional keystroke-level input constraints (e.g.
  /// `FilteringTextInputFormatter.digitsOnly` + a length limit). Defaults to
  /// none, so every existing call site is unaffected.
  final List<TextInputFormatter>? inputFormatters;

  const AppTextField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.keyboardType = TextInputType.text,
    this.prefixIcon,
    this.suffixIcon,
    this.validator,
    this.enabled = true,
    this.obscureText = false,
    this.textInputAction,
    this.onChanged,
    this.errorText,
    this.inputFormatters,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (label != null) ...[
          Text(label!, style: AppTypography.label),
          const SizedBox(height: AppSpacing.xs),
        ],
        Container(
          decoration: BoxDecoration(
            borderRadius: AppRadii.mediumBorder,
            boxShadow: AppShadows.subtle,
          ),
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            obscureText: obscureText,
            enabled: enabled,
            validator: validator,
            textInputAction: textInputAction,
            onChanged: onChanged,
            inputFormatters: inputFormatters,
            style: AppTypography.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
              hintStyle: AppTypography.bodyLarge.copyWith(
                color: AppColors.neutralMedium,
              ),
              prefixIcon: prefixIcon,
              suffixIcon: suffixIcon,
              filled: true,
              fillColor: AppColors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.m,
                vertical: AppSpacing.m,
              ),
              border: OutlineInputBorder(
                borderRadius: AppRadii.mediumBorder,
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: AppRadii.mediumBorder,
                borderSide: const BorderSide(color: AppColors.primary),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: AppRadii.mediumBorder,
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: AppRadii.mediumBorder,
                borderSide: const BorderSide(color: AppColors.error),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: AppRadii.mediumBorder,
                borderSide: const BorderSide(color: AppColors.error, width: 2),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
