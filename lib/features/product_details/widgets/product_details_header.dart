import 'package:flutter/material.dart';
import '../../../core/constants/app_assets.dart';
import '../../../core/theme/app_colors.dart';
import '../../../../core/widgets/feedback/app_toast.dart';

class ProductDetailsHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final bool isFavorite;
  final VoidCallback onFavoriteToggle;

  const ProductDetailsHeader({
    super.key,
    required this.isFavorite,
    required this.onFavoriteToggle,
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
        IconButton(
          icon: const Icon(Icons.share_outlined),
          onPressed: () {
            AppToast.info(context, 'Coming soon');
          },
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
