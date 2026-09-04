import 'package:flutter/material.dart';
import '../../../../../core/theme/app_colors.dart';
import '../models/admin_product_filter_state.dart'; // Contains AdminProductStatusFilter

class AdminCategoryFilterSheet extends StatefulWidget {
  final AdminProductStatusFilter initialStatus;
  final ValueChanged<AdminProductStatusFilter> onApply;

  const AdminCategoryFilterSheet({
    super.key,
    required this.initialStatus,
    required this.onApply,
  });

  @override
  State<AdminCategoryFilterSheet> createState() =>
      _AdminCategoryFilterSheetState();
}

class _AdminCategoryFilterSheetState extends State<AdminCategoryFilterSheet> {
  late AdminProductStatusFilter _draftStatus;

  @override
  void initState() {
    super.initState();
    _draftStatus = widget.initialStatus;
  }

  void _reset() {
    setState(() {
      _draftStatus = AdminProductStatusFilter.all;
    });
  }

  void _apply() {
    widget.onApply(_draftStatus);
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
                    'Category Filters',
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
                    // Status
                    const Text(
                      'Status',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: AdminProductStatusFilter.values.map((status) {
                        final isSelected = _draftStatus == status;
                        final label = switch (status) {
                          AdminProductStatusFilter.all => 'All',
                          AdminProductStatusFilter.active => 'Active',
                          AdminProductStatusFilter.inactive => 'Inactive',
                        };
                        return GestureDetector(
                          onTap: () {
                            setState(() {
                              _draftStatus = status;
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
                              label,
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
                      'Apply Filter',
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
}
