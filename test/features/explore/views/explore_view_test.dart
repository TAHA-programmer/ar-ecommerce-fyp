import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/explore/repositories/mock_explore_repository.dart';
import 'package:twin_ar/features/explore/viewmodels/explore_viewmodel.dart';
import 'package:twin_ar/features/explore/views/explore_view.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/widgets/navigation/customer_header.dart';
import 'package:twin_ar/features/explore/widgets/explore_search_bar.dart';
import 'package:twin_ar/features/explore/widgets/explore_product_card.dart';
import 'package:twin_ar/core/widgets/navigation/customer_bottom_navigation.dart';

void main() {
  Widget createTestWidget({
    required ValueChanged<RouteSettings> onRoutePushed,
  }) {
    final db = MockCommerceDatabase();
    return MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name != '/') {
          onRoutePushed(settings);
          // Return a dummy route so it doesn't crash
          return MaterialPageRoute(
            builder: (_) =>
                Scaffold(body: Text('Mock Route: ${settings.name}')),
          );
        }
        return null;
      },
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => CustomerShoppingState(
              MockFavoritesRepository(),
              MockCartRepository(),
            ),
          ),
          ChangeNotifierProvider<ExploreViewModel>(
            create: (context) => ExploreViewModel(
              MockExploreRepository(db),
              MockProductDetailsRepository(db, simulateDelay: false),
              context.read<CustomerShoppingState>(),
              db,
              MockCategoryRepository(),
            ),
          ),
        ],
        child: const ExploreView(),
      ),
    );
  }

  group('ExploreView Widget Tests', () {
    testWidgets('renders initial components after data loads', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(createTestWidget(onRoutePushed: (_) {}));
      await tester.pump(const Duration(seconds: 2)); // Wait for data to load
      await tester.pump();

      // Verify Header
      expect(find.byType(CustomerHeader), findsOneWidget);

      // Verify Search Bar
      expect(find.byType(ExploreSearchBar), findsOneWidget);

      // Verify bottom nav
      expect(find.byType(CustomerBottomNavigation), findsOneWidget);

      // Clean up view size
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('tapping product card pushes product details route', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;

      RouteSettings? pushedRoute;
      await tester.pumpWidget(
        createTestWidget(
          onRoutePushed: (settings) {
            pushedRoute = settings;
          },
        ),
      );
      await tester.pump(const Duration(seconds: 2)); // Wait for data to load
      await tester.pump();

      // Find the first product card
      final productCardFinder = find.byType(ExploreProductCard).first;
      expect(productCardFinder, findsOneWidget);

      // Tap the card body
      await tester.tap(productCardFinder);
      await tester.pump();

      // Verify the correct route is pushed
      expect(pushedRoute, isNotNull);
      expect(pushedRoute!.name, '/product-details');
      expect(pushedRoute!.arguments, isA<String>());

      // Clean up view size
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });
  });
}
