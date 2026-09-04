import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../core/theme/app_spacing.dart';
import '../../../../core/utils/currency_formatter.dart';
import 'admin_metric_card.dart';

class AdminPaymentSummaryCard extends StatelessWidget {
  final double paidAmount;
  final double failedAmount;
  final double successPercentage;
  final double failurePercentage;
  final VoidCallback? onTap;

  const AdminPaymentSummaryCard({
    super.key,
    required this.paidAmount,
    required this.failedAmount,
    required this.successPercentage,
    required this.failurePercentage,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        AdminMetricCard(
          icon: Icons.check_circle_outline,
          iconBackgroundColor: const Color(0xFFE6F4EA),
          iconColor: const Color(0xFF059669),
          label: 'Successful (${successPercentage.toStringAsFixed(1)}%)',
          value: CurrencyFormatter.format(paidAmount),
        ),
        const SizedBox(height: AppSpacing.s),
        AdminMetricCard(
          icon: Icons.cancel_outlined,
          iconBackgroundColor: const Color(0xFFFCE8E8),
          iconColor: AppColors.error,
          label: 'Failed (${failurePercentage.toStringAsFixed(1)}%)',
          value: CurrencyFormatter.format(failedAmount),
        ),
        const SizedBox(height: AppSpacing.s),
        AdminMetricCard(
          icon: Icons.payments_outlined,
          iconBackgroundColor: const Color(0xFFF3F6E6),
          iconColor: AppColors.primary,
          label: 'Net Revenue',
          value: CurrencyFormatter.format(paidAmount),
        ),
      ],
    );
  }
}
