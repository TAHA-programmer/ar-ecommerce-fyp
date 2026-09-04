import 'package:flutter/material.dart';
import '../../theme/app_colors.dart';
import '../../../app/routes/route_names.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';

import 'package:provider/provider.dart';

class CustomerBottomNavigation extends StatelessWidget {
  final int selectedIndex;

  const CustomerBottomNavigation({super.key, this.selectedIndex = 0});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.only(
        left: 12,
        right: 12,
        bottom: MediaQuery.of(context).padding.bottom + 12,
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(40),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _buildNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home,
            isActive: selectedIndex == 0,
            onTap: () {
              if (selectedIndex != 0) {
                Navigator.pushReplacementNamed(context, RouteNames.home);
              }
            },
          ),
          _buildNavItem(
            icon: Icons.explore_outlined,
            activeIcon: Icons.explore,
            isActive: selectedIndex == 1,
            onTap: () {
              if (selectedIndex != 1) {
                Navigator.pushReplacementNamed(context, RouteNames.explore);
              }
            },
          ),
          Consumer<CustomerShoppingState>(
            builder: (context, shoppingState, child) {
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  _buildNavItem(
                    icon: Icons.shopping_cart_outlined,
                    activeIcon: Icons.shopping_cart,
                    isActive: selectedIndex == 2,
                    onTap: () {
                      if (selectedIndex != 2) {
                        Navigator.pushReplacementNamed(
                          context,
                          RouteNames.cart,
                        );
                      }
                    },
                  ),
                  if (shoppingState.cartCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        child: Text(
                          '${shoppingState.cartCount}',
                          style: const TextStyle(
                            color: AppColors.white,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
          _buildNavItem(
            icon: Icons.person_outline,
            activeIcon: Icons.person,
            isActive: selectedIndex == 3,
            onTap: () {
              if (selectedIndex != 3) {
                Navigator.pushReplacementNamed(context, RouteNames.profile);
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildNavItem({
    required IconData icon,
    required IconData activeIcon,
    required bool isActive,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        padding: const EdgeInsets.all(8),
        child: Icon(
          isActive ? activeIcon : icon,
          color: isActive ? AppColors.primary : AppColors.textPrimary,
          size: 26,
        ),
      ),
    );
  }
}
