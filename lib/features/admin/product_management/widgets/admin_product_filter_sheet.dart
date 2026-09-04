import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../../../../../core/models/product/product_category.dart';
import '../models/admin_product_filter_state.dart';

class AdminProductFilterSheet extends StatefulWidget {
  final AdminProductFilterState initialFilterState;
  final ValueChanged<AdminProductFilterState> onApply;

  const AdminProductFilterSheet({
    super.key,
    required this.initialFilterState,
    required this.onApply,
  });

  @override
  State<AdminProductFilterSheet> createState() =>
      _AdminProductFilterSheetState();
}

class _AdminProductFilterSheetState extends State<AdminProductFilterSheet> {
  late AdminProductFilterState _draftState;

  @override
  void initState() {
    super.initState();
    _draftState = widget.initialFilterState;
  }

  void _reset() {
    setState(() {
      _draftState = AdminProductFilterState.defaultState();
    });
  }

  void _apply() {
    widget.onApply(_draftState);
    Navigator.of(context).pop();
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
                      children: [
                        _buildCategoryChip(
                          'All',
                          _draftState.category == null,
                          () {
                            setState(() {
                              _draftState = _draftState.copyWith(
                                clearCategory: true,
                              );
                            });
                          },
                        ),
                        ...ProductCategory.values
                            .where((cat) => cat != ProductCategory.all)
                            .map((cat) {
                              final isSelected = _draftState.category == cat;
                              return _buildCategoryChip(
                                cat.label,
                                isSelected,
                                () {
                                  setState(() {
                                    _draftState = _draftState.copyWith(
                                      category: cat,
                                      clearCategory: false,
                                    );
                                  });
                                },
                              );
                            }),
                      ],
                    ),
                    const SizedBox(height: 20),

                    // Status
                    _buildSectionTitle('Status'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AdminProductStatusFilter.values.map((status) {
                        final isSelected = _draftState.status == status;
                        final label = switch (status) {
                          AdminProductStatusFilter.all => 'All',
                          AdminProductStatusFilter.active => 'Active',
                          AdminProductStatusFilter.inactive => 'Inactive',
                        };
                        return _buildCategoryChip(label, isSelected, () {
                          setState(() {
                            _draftState = _draftState.copyWith(status: status);
                          });
                        });
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // Stock
                    _buildSectionTitle('Stock'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AdminProductStockFilter.values.map((stock) {
                        final isSelected = _draftState.stock == stock;
                        final label = switch (stock) {
                          AdminProductStockFilter.all => 'All',
                          AdminProductStockFilter.inStock => 'In Stock',
                          AdminProductStockFilter.lowStock => 'Low Stock',
                          AdminProductStockFilter.outOfStock => 'Out of Stock',
                        };
                        return _buildCategoryChip(label, isSelected, () {
                          setState(() {
                            _draftState = _draftState.copyWith(stock: stock);
                          });
                        });
                      }).toList(),
                    ),
                    const SizedBox(height: 20),

                    // AR Type
                    _buildSectionTitle('AR Type'),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AdminProductArFilter.values.map((arType) {
                        final isSelected = _draftState.arType == arType;
                        final label = switch (arType) {
                          AdminProductArFilter.all => 'All',
                          AdminProductArFilter.none => 'No AR',
                          AdminProductArFilter.roomAr => 'Room AR',
                          AdminProductArFilter.virtualTryOn => 'Virtual Try-On',
                        };
                        return _buildCategoryChip(label, isSelected, () {
                          setState(() {
                            _draftState = _draftState.copyWith(arType: arType);
                          });
                        });
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

  Widget _buildCategoryChip(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.neutralLight,
            width: 1,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Inter',
            color: AppColors.textPrimary,
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
