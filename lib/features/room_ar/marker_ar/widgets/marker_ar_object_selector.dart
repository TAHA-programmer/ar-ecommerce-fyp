import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';
import '../models/marker_ar_object.dart';

/// Themed object picker for the Marker-AR screen. Horizontally scrollable so
/// every chip keeps a full 48 dp tap target and the row can never overflow on a
/// narrow phone (Infinix). Lime fill marks the selection, matching the TWin AR
/// segmented-control language.
class MarkerArObjectSelector extends StatelessWidget {
  final List<MarkerArObject> objects;
  final MarkerArObject selected;
  final ValueChanged<MarkerArObject> onSelected;

  const MarkerArObjectSelector({
    super.key,
    required this.objects,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
      child: Row(
        children: [
          for (final o in objects) ...[
            _Chip(
              key: ValueKey('marker-ar-object-${o.name}'),
              object: o,
              selected: o == selected,
              onTap: () => onSelected(o),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final MarkerArObject object;
  final bool selected;
  final VoidCallback onTap;

  const _Chip({
    super.key,
    required this.object,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? AppColors.white : AppColors.white;
    return Material(
      color: selected
          ? AppColors.primary
          : AppColors.black.withValues(alpha: 0.35),
      borderRadius: AppRadii.pillBorder,
      child: InkWell(
        borderRadius: AppRadii.pillBorder,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 40),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s,
            vertical: AppSpacing.xs,
          ),
          decoration: BoxDecoration(
            borderRadius: AppRadii.pillBorder,
            border: Border.all(
              color: selected
                  ? AppColors.primaryDark
                  : AppColors.white.withValues(alpha: 0.25),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(object.icon, size: 16, color: fg),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                object.label,
                style: AppTypography.label.copyWith(
                  color: fg,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
