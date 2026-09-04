import 'package:flutter/material.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/models/product/product_color_option.dart';

class ProductColorSelector extends StatelessWidget {
  final List<ProductColorOption> availableColors;
  final ProductColorOption? selectedColor;
  final ValueChanged<ProductColorOption> onColorSelected;

  const ProductColorSelector({
    super.key,
    required this.availableColors,
    required this.selectedColor,
    required this.onColorSelected,
  });

  Color _getColorValue(ProductColorOption option) {
    switch (option) {
      case ProductColorOption.beige:
        return const Color(0xFFE5D3C1);
      case ProductColorOption.gray:
        return Colors.grey;
      case ProductColorOption.black:
        return Colors.black;
      case ProductColorOption.brown:
        return Colors.brown;
      case ProductColorOption.blue:
        return const Color(0xFF6A8EAE); // Sky blue
      case ProductColorOption.green:
        return Colors.green;
      case ProductColorOption.pink:
        return Colors.pinkAccent;
    }
  }

  String _getColorName(ProductColorOption option) {
    switch (option) {
      case ProductColorOption.beige:
        return 'Beige';
      case ProductColorOption.gray:
        return 'Gray';
      case ProductColorOption.black:
        return 'Black';
      case ProductColorOption.brown:
        return 'Brown';
      case ProductColorOption.blue:
        return 'Sky Blue';
      case ProductColorOption.green:
        return 'Green';
      case ProductColorOption.pink:
        return 'Pink';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        RichText(
          text: TextSpan(
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textPrimary,
            ),
            children: [
              const TextSpan(text: 'Color: '),
              TextSpan(
                text: selectedColor != null
                    ? _getColorName(selectedColor!)
                    : '',
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          children: availableColors.map((color) {
            final isSelected = color == selectedColor;
            final colorValue = _getColorValue(color);
            return GestureDetector(
              onTap: () => onColorSelected(color),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: colorValue,
                      border: Border.all(
                        color: isSelected
                            ? AppColors.primary
                            : AppColors.neutralMediumLight,
                        width: isSelected ? 2 : 1,
                      ),
                    ),
                  ),
                  if (isSelected)
                    Positioned(
                      bottom: -2,
                      right: -2,
                      child: Container(
                        padding: const EdgeInsets.all(2),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(
                          Icons.check,
                          color: Colors.white,
                          size: 10,
                        ),
                      ),
                    ),
                ],
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}
