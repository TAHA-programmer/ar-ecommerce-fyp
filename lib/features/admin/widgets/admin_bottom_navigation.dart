import 'package:flutter/material.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_typography.dart';

class AdminBottomNavigation extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTap;

  const AdminBottomNavigation({
    super.key,
    required this.currentIndex,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return BottomNavigationBar(
      currentIndex: currentIndex,
      onTap: onTap,
      type: BottomNavigationBarType.fixed,
      backgroundColor: AppColors.surface,
      selectedItemColor: AppColors.primary,
      unselectedItemColor:
          AppColors.neutralDark, // Standard AppColors neutral for unselected
      showUnselectedLabels: true,
      selectedLabelStyle: AppTypography.caption.copyWith(
        fontWeight: FontWeight.bold,
      ),
      unselectedLabelStyle: AppTypography.caption,
      items: const [
        BottomNavigationBarItem(
          icon: Icon(Icons.grid_view_rounded), // Matches 2x2 grid in Figma
          label: 'Dashboard',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            Icons.shopping_bag_outlined,
          ), // Matches shopping bag in Figma
          label: 'Products',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            Icons.inventory_2_outlined,
          ), // Matches inventory box in Figma
          label: 'Inventory',
        ),
        BottomNavigationBarItem(
          icon: Icon(
            Icons.receipt_long_outlined,
          ), // Matches clipboard/orders in Figma
          label: 'Orders',
        ),
      ],
    );
  }
}
