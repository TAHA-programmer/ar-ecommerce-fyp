import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import 'app_text_field.dart';

class AppPasswordField extends StatefulWidget {
  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? Function(String?)? validator;
  final TextInputAction? textInputAction;

  const AppPasswordField({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.validator,
    this.textInputAction,
  });

  @override
  State<AppPasswordField> createState() => _AppPasswordFieldState();
}

class _AppPasswordFieldState extends State<AppPasswordField> {
  bool _obscureText = true;

  @override
  Widget build(BuildContext context) {
    return AppTextField(
      controller: widget.controller,
      label: widget.label,
      hint: widget.hint,
      obscureText: _obscureText,
      validator: widget.validator,
      textInputAction: widget.textInputAction,
      keyboardType: TextInputType.visiblePassword,
      prefixIcon: Icon(Icons.lock_outline, color: AppColors.primary),
      suffixIcon: IconButton(
        icon: Icon(
          _obscureText
              ? Icons.visibility_off_outlined
              : Icons.visibility_outlined,
          color: AppColors.textSecondary,
        ),
        onPressed: () {
          setState(() {
            _obscureText = !_obscureText;
          });
        },
      ),
    );
  }
}
