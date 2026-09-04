import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../theme/app_radii.dart';
import '../../theme/app_sizes.dart';
import '../../theme/app_typography.dart';
import '../../theme/app_spacing.dart';

class AppPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final Widget? leadingIcon;
  final Widget? trailingIcon;
  final bool fullWidth;
  final TextStyle? textStyle;

  const AppPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.leadingIcon,
    this.trailingIcon,
    this.fullWidth = true,
    this.textStyle,
  });

  @override
  Widget build(BuildContext context) {
    final Widget buttonContent = Row(
      mainAxisSize: fullWidth ? MainAxisSize.max : MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (isLoading)
          const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.white),
            ),
          )
        else ...[
          if (leadingIcon != null) ...[
            leadingIcon!,
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style:
                textStyle ??
                AppTypography.label.copyWith(color: AppColors.white),
          ),
          if (trailingIcon != null) ...[
            const SizedBox(width: AppSpacing.xs),
            trailingIcon!,
          ],
        ],
      ],
    );

    final button = Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: AppRadii.pillBorder,
        child: Container(
          height: AppSizes.buttonHeight,
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.l),
          decoration: BoxDecoration(
            borderRadius: AppRadii.pillBorder,
            gradient: (onPressed != null && !isLoading)
                ? const LinearGradient(
                    colors: [AppColors.primaryLight, AppColors.primaryDarker],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : null,
            color: (onPressed == null || isLoading)
                ? AppColors.neutralMediumLight
                : null,
          ),
          child: Center(
            widthFactor: fullWidth ? null : 1.0,
            child: buttonContent,
          ),
        ),
      ),
    );

    if (fullWidth) {
      return SizedBox(width: double.infinity, child: button);
    }

    return button;
  }
}
