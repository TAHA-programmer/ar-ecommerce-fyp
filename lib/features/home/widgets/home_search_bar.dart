import 'package:flutter/material.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../../app/routes/explore_launch_intent.dart';
import '../../../../app/routes/route_names.dart';

class HomeSearchBar extends StatefulWidget {
  const HomeSearchBar({super.key});

  @override
  State<HomeSearchBar> createState() => _HomeSearchBarState();
}

class _HomeSearchBarState extends State<HomeSearchBar> {
  final TextEditingController _controller = TextEditingController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submitSearch(String query) {
    // Every Home → Explore entry starts from a neutral Explore state (see
    // `ExploreLaunchIntent.fromHome`), so a search from Home never inherits
    // the Explore tab's persisted / Figma-default filters.
    if (query.trim().isNotEmpty) {
      Navigator.pushNamed(
        context,
        RouteNames.explore,
        arguments: ExploreLaunchIntent(
          fromHome: true,
          searchQuery: query.trim(),
        ),
      );
    } else {
      Navigator.pushNamed(
        context,
        RouteNames.explore,
        arguments: const ExploreLaunchIntent(fromHome: true),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      height: 50,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          GestureDetector(
            onTap: () => _submitSearch(_controller.text),
            child: const Icon(Icons.search, color: AppColors.textSecondary),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _controller,
              onSubmitted: _submitSearch,
              decoration: const InputDecoration(
                hintText: 'Search Furniture, Decor, Clothing...',
                hintStyle: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ),
              style: const TextStyle(
                fontSize: 14,
                color: AppColors.textPrimary,
              ),
              maxLines: 1,
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () {
              Navigator.pushNamed(
                context,
                RouteNames.explore,
                arguments: const ExploreLaunchIntent(
                  fromHome: true,
                  openFilterSheet: true,
                ),
              );
            },
            child: const Icon(Icons.tune, color: AppColors.primary),
          ),
        ],
      ),
    );
  }
}
