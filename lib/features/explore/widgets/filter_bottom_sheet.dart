import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../models/explore_filter_state.dart';
import '../../../core/models/product/product_category.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';

class FilterBottomSheet extends StatefulWidget {
  final ExploreFilterState initialFilterState;
  final ValueChanged<ExploreFilterState> onApply;

  const FilterBottomSheet({
    super.key,
    required this.initialFilterState,
    required this.onApply,
  });

  @override
  State<FilterBottomSheet> createState() => _FilterBottomSheetState();
}

class _FilterBottomSheetState extends State<FilterBottomSheet> {
  late ExploreFilterState _draftState;

  @override
  void initState() {
    super.initState();
    _draftState = widget.initialFilterState;
  }

  void _reset() {
    setState(() {
      _draftState = ExploreFilterState.defaultState();
    });
  }

  void _apply() {
    widget.onApply(_draftState);
    Navigator.of(context).pop();
  }

  Color _getColorForOption(ProductColorOption option) {
    switch (option) {
      case ProductColorOption.beige:
        return const Color(0xFFF5F5DC);
      case ProductColorOption.gray:
        return Colors.grey;
      case ProductColorOption.black:
        return Colors.black;
      case ProductColorOption.brown:
        return Colors.brown;
      case ProductColorOption.blue:
        return Colors.blue;
      case ProductColorOption.green:
        return Colors.green;
      case ProductColorOption.pink:
        return Colors.pink;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Drag Indicator
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 10),
                width: 32,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.neutralLight,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            // Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Filters',
                    style: TextStyle(
                      fontFamily: 'Inter',
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.of(context).pop(),
                    child: const Icon(
                      Icons.close,
                      color: AppColors.textPrimary,
                      size: 20,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Scrollable Content
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Category
                    _buildSectionTitle('Category'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children:
                          [
                            ProductCategory.furniture,
                            ProductCategory.rugs,
                            ProductCategory.decor,
                            ProductCategory.lighting,
                            ProductCategory.clothing,
                          ].map((cat) {
                            final isSelected = _draftState.category == cat;
                            return GestureDetector(
                              onTap: () {
                                setState(() {
                                  _draftState = _draftState.copyWith(
                                    category: isSelected
                                        ? ProductCategory.all
                                        : cat,
                                  );
                                });
                              },
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: isSelected
                                      ? AppColors.primary
                                      : Colors.white,
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: isSelected
                                        ? AppColors.primary
                                        : AppColors.neutralLight,
                                    width: 1,
                                  ),
                                ),
                                child: Text(
                                  cat.label,
                                  style: TextStyle(
                                    fontFamily: 'Inter',
                                    color: AppColors.textPrimary,
                                    fontSize: 12,
                                    fontWeight: isSelected
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Price Range
                    _buildSectionTitle('Price Range'),
                    const SizedBox(height: 4),
                    SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 2,
                        thumbShape: const RoundSliderThumbShape(
                          enabledThumbRadius: 6,
                        ),
                        overlayShape: const RoundSliderOverlayShape(
                          overlayRadius: 14,
                        ),
                      ),
                      child: RangeSlider(
                        values: RangeValues(
                          _draftState.minimumPrice,
                          _draftState.maximumPrice,
                        ),
                        min: 0,
                        max: 50000,
                        divisions: 50,
                        activeColor: AppColors.primary,
                        inactiveColor: AppColors.primary.withValues(alpha: 0.2),
                        onChanged: (values) {
                          setState(() {
                            _draftState = _draftState.copyWith(
                              minimumPrice: values.start,
                              maximumPrice: values.end,
                            );
                          });
                        },
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Rs ${_draftState.minimumPrice.toInt()}',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                        Text(
                          'Rs ${_draftState.maximumPrice.toInt()}+',
                          style: const TextStyle(
                            fontFamily: 'Inter',
                            fontSize: 12,
                            color: AppColors.textSecondary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Toggles in ONE COMPACT HORIZONTAL ROW
                    Row(
                      children: [
                        _buildCompactToggle(
                          'In Stock',
                          _draftState.inStockOnly,
                          (val) {
                            setState(
                              () => _draftState = _draftState.copyWith(
                                inStockOnly: val,
                              ),
                            );
                          },
                        ),
                        Container(
                          width: 1,
                          height: 16,
                          color: AppColors.neutralLight,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        _buildCompactToggle(
                          'AR Available',
                          _draftState.arAvailable,
                          (val) {
                            setState(
                              () => _draftState = _draftState.copyWith(
                                arAvailable: val,
                              ),
                            );
                          },
                        ),
                        Container(
                          width: 1,
                          height: 16,
                          color: AppColors.neutralLight,
                          margin: const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        _buildCompactToggle(
                          'Try-On',
                          _draftState.tryOnAvailable,
                          (val) {
                            setState(
                              () => _draftState = _draftState.copyWith(
                                tryOnAvailable: val,
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    const Divider(height: 1, color: AppColors.neutralLight),
                    const SizedBox(height: 20),

                    // Sizes
                    _buildSectionTitle('Sizes'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      children: ProductSize.values.map((size) {
                        final isSelected = _draftState.selectedSizes.contains(
                          size,
                        );
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              final newSizes = Set<ProductSize>.from(
                                _draftState.selectedSizes,
                              );
                              if (isSelected) {
                                newSizes.remove(size);
                              } else {
                                newSizes.add(size);
                              }
                              _draftState = _draftState.copyWith(
                                selectedSizes: newSizes,
                              );
                            });
                          },
                          child: Container(
                            width: 36,
                            height: 32,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.white,
                              borderRadius: BorderRadius.circular(
                                6,
                              ), // Not circles
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : AppColors.neutralLight,
                                width: 1,
                              ),
                            ),
                            child: Center(
                              child: Text(
                                size.label,
                                style: TextStyle(
                                  fontFamily: 'Inter',
                                  color: AppColors.textPrimary,
                                  fontSize: 12,
                                  fontWeight: isSelected
                                      ? FontWeight.w600
                                      : FontWeight.w400,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Colors
                    _buildSectionTitle('Colors'),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      children: ProductColorOption.values.map((colorOption) {
                        final isSelected = _draftState.selectedColors.contains(
                          colorOption,
                        );
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              final newColors = Set<ProductColorOption>.from(
                                _draftState.selectedColors,
                              );
                              if (isSelected) {
                                newColors.remove(colorOption);
                              } else {
                                newColors.add(colorOption);
                              }
                              _draftState = _draftState.copyWith(
                                selectedColors: newColors,
                              );
                            });
                          },
                          child: Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border: Border.all(
                                color: isSelected
                                    ? AppColors.primary
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            padding: const EdgeInsets.all(2),
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _getColorForOption(colorOption),
                                border: Border.all(
                                  color: AppColors.neutralLight,
                                  width: 0.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
            // Bottom Actions
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: _reset,
                    child: const Text(
                      'Clear All',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: AppColors.primary,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  const Spacer(),
                  ElevatedButton(
                    onPressed: _apply,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 40,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      elevation: 0,
                    ),
                    child: const Text(
                      'Apply Filters',
                      style: TextStyle(
                        fontFamily: 'Inter',
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(
      title,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.bold,
        color: AppColors.textPrimary,
      ),
    );
  }

  Widget _buildCompactToggle(
    String title,
    bool value,
    ValueChanged<bool> onChanged,
  ) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: value ? AppColors.primary : Colors.white,
              borderRadius: BorderRadius.circular(3),
              border: Border.all(
                color: value ? AppColors.primary : AppColors.neutralLight,
              ),
            ),
            child: value
                ? const Icon(Icons.check, size: 10, color: Colors.black)
                : null,
          ),
          const SizedBox(width: 6),
          Text(
            title,
            style: const TextStyle(
              fontFamily: 'Inter',
              fontSize: 10,
              fontWeight: FontWeight.w500,
              color: AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
