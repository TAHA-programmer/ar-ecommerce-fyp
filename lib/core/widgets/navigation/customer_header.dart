import 'package:flutter/material.dart';
import '../../constants/app_assets.dart';
import '../../theme/app_colors.dart';
import '../../../app/routes/route_names.dart';

class CustomerHeader extends StatelessWidget {
  final int cartCount;

  const CustomerHeader({super.key, required this.cartCount});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 8,
        left: 16,
        right: 16,
        bottom: 8,
      ),
      color: Colors.white,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // Logo
          Image.asset(AppAssets.headerLogo, height: 32, fit: BoxFit.contain),
          // Actions
          Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.favorite_border,
                  color: AppColors.textPrimary,
                ),
                onPressed: () {
                  Navigator.pushNamed(context, RouteNames.favorites);
                },
              ),
              const SizedBox(width: 8),
              Stack(
                alignment: Alignment.center,
                clipBehavior: Clip.none,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.shopping_cart_outlined,
                      color: AppColors.textPrimary,
                    ),
                    onPressed: () {
                      Navigator.pushNamed(context, RouteNames.cart);
                    },
                  ),
                  if (cartCount > 0)
                    Positioned(
                      top: 4,
                      right: 4,
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(
                          color: AppColors.primary,
                          shape: BoxShape.circle,
                        ),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '$cartCount',
                          style: const TextStyle(
                            color: AppColors
                                .textPrimary, // lime badge usually has dark text
                            fontSize: 10,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
