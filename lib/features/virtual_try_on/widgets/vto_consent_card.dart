import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/fields/app_checkbox.dart';

/// Blocking, per-session Virtual Try-On consent (Phase 9.3 Stage 5, developer
/// decision D5) — must be re-checked every visit; never persisted or
/// remembered across sessions. Copy is factually accurate to the shipped
/// architecture (Gemini, server-side, deleted immediately after generation) —
/// it must never claim on-device processing or "not stored", which the
/// earlier prototype copy incorrectly did.
class VtoConsentCard extends StatelessWidget {
  final bool checked;
  final ValueChanged<bool> onChanged;

  const VtoConsentCard({
    super.key,
    required this.checked,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: checked ? const Color(0xFFF6F8E8) : const Color(0xFFF5F5F5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: checked ? AppColors.primary : AppColors.neutralLight,
          width: checked ? 1.5 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.lock_outline, color: AppColors.primaryDark),
              const SizedBox(width: 8),
              Text(
                'Before you continue',
                style: AppTypography.bodyMedium.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          AppCheckbox(
            value: checked,
            onChanged: (v) => onChanged(v ?? false),
            labelText:
                "I understand my photo will be sent to a secure AI service "
                "(Google Gemini) to generate this preview. My photo is "
                "deleted immediately after generating the preview, and the "
                "generated preview is deleted when I close it or after 24 "
                "hours. This is a visual preview only — not an accurate fit "
                "or sizing guarantee.",
          ),
        ],
      ),
    );
  }
}
