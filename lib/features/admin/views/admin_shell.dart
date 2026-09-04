import 'package:flutter/material.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import '../widgets/admin_header.dart';
import '../widgets/admin_bottom_navigation.dart';

class AdminShell extends StatelessWidget {
  final Widget child;
  final int currentIndex;
  final String title;
  final bool showGreeting;
  final VoidCallback? onBack;

  const AdminShell({
    super.key,
    required this.child,
    required this.currentIndex,
    required this.title,
    this.showGreeting = false,
    this.onBack,
  });

  void _onTabTapped(BuildContext context, int index) {
    if (index == currentIndex) return;

    String routeName;
    switch (index) {
      case 0:
        routeName = RouteNames.adminDashboard;
        break;
      case 1:
        routeName = RouteNames.adminProducts;
        break;
      case 2:
        routeName = RouteNames.adminInventory;
        break;
      case 3:
        routeName = RouteNames.adminOrders;
        break;
      default:
        return;
    }

    // Replacement routing to avoid endless stacking of top-level Admin tabs
    Navigator.of(context).pushReplacementNamed(routeName);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AdminHeader(
        title: title,
        showGreeting: showGreeting,
        onBack: onBack,
      ),
      body: SafeArea(child: child),
      bottomNavigationBar: AdminBottomNavigation(
        currentIndex: currentIndex,
        onTap: (index) => _onTabTapped(context, index),
      ),
    );
  }
}
