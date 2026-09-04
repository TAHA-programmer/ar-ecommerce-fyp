import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/core/theme/app_spacing.dart';

class AdminNotificationSheet extends StatelessWidget {
  const AdminNotificationSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final db = context.watch<CommerceDatabase>();

    // Derive simple notifications from DB
    final List<String> notifications = [];

    if (db.orders.isNotEmpty) {
      notifications.add('New order received: ${db.orders.last.id}');
    }

    final lowStockCount = db.products
        .where((p) => p.stockQuantity > 0 && p.stockQuantity <= 5)
        .length;
    if (lowStockCount > 0) {
      notifications.add('$lowStockCount products are low in stock.');
    }

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Notifications',
                  style: AppTypography.title.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ),
            const Divider(),
            if (notifications.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xl),
                child: Center(
                  child: Text(
                    'No new notifications',
                    style: AppTypography.bodyMedium.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              ...notifications.map(
                (msg) => ListTile(
                  leading: const CircleAvatar(
                    backgroundColor: AppColors.primaryLight,
                    radius: 16,
                    child: Icon(
                      Icons.notifications,
                      color: AppColors.primaryDark,
                      size: 16,
                    ),
                  ),
                  title: Text(msg, style: AppTypography.bodyMedium),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
