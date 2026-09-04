import 'package:flutter/material.dart';

import '../../../../core/models/order/order_model.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_radii.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/theme/app_typography.dart';

class AdminOrdersFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final OrderStatus? statusFilter;
  final ValueChanged<OrderStatus?> onStatusFilterChanged;
  final PaymentStatus? paymentStatusFilter;
  final ValueChanged<PaymentStatus?> onPaymentStatusFilterChanged;

  const AdminOrdersFilterBar({
    super.key,
    required this.searchController,
    required this.onSearchChanged,
    required this.statusFilter,
    required this.onStatusFilterChanged,
    required this.paymentStatusFilter,
    required this.onPaymentStatusFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          key: const Key('admin_orders_search_field'),
          controller: searchController,
          onChanged: onSearchChanged,
          style: AppTypography.bodySmall,
          decoration: InputDecoration(
            hintText: 'Search by Order ID or Customer...',
            hintMaxLines: 1,
            hintStyle: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
              overflow: TextOverflow.ellipsis,
            ),
            prefixIcon: const Icon(
              Icons.search,
              color: AppColors.textSecondary,
            ),
            filled: true,
            fillColor: AppColors.white,
            contentPadding: const EdgeInsets.symmetric(
              vertical: 0,
              horizontal: AppSpacing.m,
            ),
            border: OutlineInputBorder(
              borderRadius: AppRadii.mediumBorder,
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: AppRadii.mediumBorder,
              borderSide: const BorderSide(color: AppColors.primary),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: AppRadii.mediumBorder,
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterPill(
                key: const Key('order_status_filter_all'),
                label: 'All',
                isSelected: statusFilter == null,
                onTap: () => onStatusFilterChanged(null),
              ),
              ...OrderStatus.values.map(
                (status) => Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: _FilterPill(
                    key: Key('order_status_filter_${status.name}'),
                    label: status.displayName,
                    isSelected: statusFilter == status,
                    onTap: () => onStatusFilterChanged(status),
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              _FilterPill(
                key: const Key('payment_status_filter_all'),
                label: 'All Payments',
                isSelected: paymentStatusFilter == null,
                onTap: () => onPaymentStatusFilterChanged(null),
              ),
              ...PaymentStatus.values.map(
                (status) => Padding(
                  padding: const EdgeInsets.only(left: AppSpacing.xs),
                  child: _FilterPill(
                    key: Key('payment_status_filter_${status.name}'),
                    label: status.displayName,
                    isSelected: paymentStatusFilter == status,
                    onTap: () => onPaymentStatusFilterChanged(status),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _FilterPill({
    super.key,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s,
          vertical: AppSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.primary : AppColors.white,
          borderRadius: AppRadii.pillBorder,
          border: Border.all(
            color: isSelected
                ? AppColors.primary
                : AppColors.primary.withValues(alpha: 0.5),
          ),
        ),
        child: Text(
          label,
          style: AppTypography.bodySmall.copyWith(
            color: isSelected ? AppColors.white : AppColors.textPrimary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}
