import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/models/product/product_specification.dart';

class ProductSpecificationsCard extends StatelessWidget {
  final List<ProductSpecification> specifications;

  const ProductSpecificationsCard({super.key, required this.specifications});

  IconData _getIconForSpec(String label) {
    final lowerLabel = label.toLowerCase();
    if (lowerLabel.contains('material') || lowerLabel.contains('fabric')) {
      return Icons.layers_outlined;
    }
    if (lowerLabel.contains('dimension')) {
      return Icons.straighten_outlined;
    }
    if (lowerLabel.contains('bulb')) {
      return Icons.lightbulb_outline;
    }
    return Icons.info_outline;
  }

  @override
  Widget build(BuildContext context) {
    if (specifications.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16.0),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(
          color: AppColors.primary.withValues(alpha: 0.3), // Pale lime border
          width: 1,
        ),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: List.generate(specifications.length, (index) {
          final spec = specifications[index];
          return Padding(
            padding: EdgeInsets.only(
              bottom: index < specifications.length - 1 ? 12.0 : 0,
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  _getIconForSpec(spec.label),
                  size: 18,
                  color: AppColors.textPrimary,
                ),
                const SizedBox(width: 8),
                Text(
                  spec.label,
                  style: AppTypography.bodySmall.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const Spacer(),
                Expanded(
                  flex: 2,
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Text(
                        spec.value,
                        textAlign: TextAlign.right,
                        style: AppTypography.bodySmall.copyWith(
                          color: AppColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ),
    );
  }
}
