import 'package:flutter/material.dart';
import '../../theme/app_spacing.dart';
import '../../theme/app_typography.dart';

class AppCheckbox extends StatelessWidget {
  final bool value;
  final ValueChanged<bool?> onChanged;
  final Widget? labelWidget;
  final String? labelText;

  const AppCheckbox({
    super.key,
    required this.value,
    required this.onChanged,
    this.labelWidget,
    this.labelText,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final bool isUnbounded = constraints.maxWidth == double.infinity;

        return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            SizedBox(
              height: 24,
              width: 24,
              child: Checkbox(
                value: value,
                onChanged: onChanged,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
            ),
            if (labelWidget != null || labelText != null) ...[
              const SizedBox(width: AppSpacing.xs),
              if (isUnbounded)
                labelWidget ?? Text(labelText!, style: AppTypography.bodyMedium)
              else
                Flexible(
                  child:
                      labelWidget ??
                      Text(labelText!, style: AppTypography.bodyMedium),
                ),
            ],
          ],
        );
      },
    );
  }
}
