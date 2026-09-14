import 'package:flutter/material.dart';
import '../../../app/routes/route_names.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_colors.dart';

class ProductDetailsHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;

  /// Live cart line count, mirroring [CustomerHeader]'s badge — sourced by
  /// the caller from `CustomerShoppingState.cartCount` so every app bar
  /// (Home/Explore/Cart's own header and this one) shows the same number.
  final int cartCount;

  const ProductDetailsHeader({
    super.key,
    required this.isFavorite,
    required this.onFavoriteToggle,
    required this.cartCount,
  });

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      elevation: 0,
      iconTheme: const IconThemeData(color: AppColors.textPrimary),
      titleSpacing: 0, // Reduces space between back button and logo
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset(AppAssets.headerLogo, height: 24, fit: BoxFit.contain),
        ],
      ),
      actions: [
        IconButton(
          icon: Icon(
            isFavorite ? Icons.favorite : Icons.favorite_border,
            color: isFavorite ? AppColors.primary : AppColors.textPrimary,
          ),
          onPressed: onFavoriteToggle,
        ),
        Stack(
          alignment: Alignment.center,
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(
                Icons.shopping_cart_outlined,
                color: AppColors.textPrimary,
              ),
              onPressed: () => Navigator.pushNamed(context, RouteNames.cart),
            ),
            if (cartCount > 0)
              Positioned(
                top: 6,
                right: 6,
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
                      color: AppColors.textPrimary,
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
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
