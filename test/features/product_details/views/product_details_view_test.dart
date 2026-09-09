import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/category_repository.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/features/product_details/views/product_details_view.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/widgets/navigation/customer_bottom_navigation.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/product_details/repositories/recently_viewed_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_recently_viewed_repository.dart';

void main() {
  Widget createTestWidget(String productId, {MockCommerceDatabase? db}) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          Provider<ProductDetailsRepository>(
            create: (_) => MockProductDetailsRepository(
              db ?? MockCommerceDatabase(),
              simulateDelay: false,
            ),
          ),
          ChangeNotifierProvider<CategoryRepository>(
            create: (_) => MockCategoryRepository(),
          ),
          Provider<RecentlyViewedRepository>(
            create: (_) => MockRecentlyViewedRepository(),
          ),
          ChangeNotifierProvider(
            create: (_) => CustomerShoppingState(
              MockFavoritesRepository(),
              MockCartRepository(),
            ),
          ),
        ],
        child: ProductDetailsView(productId: productId),
      ),
    );
  }

  group('ProductDetailsView Widget Tests', () {
    testWidgets('Luna Accent Chair renders correctly', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(createTestWidget('luna-accent-chair'));
      await tester.pumpAndSettle();

      // Header and Logo
      expect(find.byType(AppBar), findsOneWidget);
      expect(find.byType(Image), findsWidgets); // Header logo + gallery images

      // Favorite and Share in header
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(find.byIcon(Icons.share_outlined), findsOneWidget);

      // NO CustomerBottomNavigation
      expect(find.byType(CustomerBottomNavigation), findsNothing);

      // Data checks
      expect(find.text('Luna Accent Chair'), findsOneWidget);
      expect(find.text('Rs 12,000/-'), findsOneWidget);
      expect(find.text('Rs 16,000/-'), findsOneWidget);
      expect(find.text('25% OFF'), findsOneWidget);

      // Specifications
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('Premium Fabric, Solid Wood'), findsOneWidget);
      expect(find.text('Dimensions'), findsOneWidget);

      // Actions
      expect(find.text('View in Your Room'), findsOneWidget);
      expect(find.textContaining('Add to Cart'), findsOneWidget);

      // Try on should NOT be present
      expect(find.text('Try It On'), findsNothing);

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('Mens Oxford Shirt renders correctly', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(createTestWidget('mens-oxford-shirt'));
      await tester.pumpAndSettle();

      // NO CustomerBottomNavigation
      expect(find.byType(CustomerBottomNavigation), findsNothing);

      // Data checks
      expect(find.text('Men\'s Oxford Shirt'), findsOneWidget);
      expect(find.text('Rs 2,200/-'), findsOneWidget);
      expect(find.text('Rs 3,200/-'), findsOneWidget);
      expect(find.text('31% OFF'), findsOneWidget);

      // Sizes
      expect(find.text('S'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('XL'), findsOneWidget);
      expect(find.text('XXL'), findsOneWidget);

      // Benefits
      expect(find.textContaining('7-Day Easy'), findsOneWidget);
      expect(find.textContaining('Secure'), findsOneWidget);
      expect(find.textContaining('Free Shipping'), findsOneWidget);

      // Actions
      expect(find.text('Try It On'), findsOneWidget);
      expect(find.textContaining('Add to Cart'), findsOneWidget);

      // Room AR should NOT be present
      expect(find.text('View in your Room'), findsNothing);

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('Standard product renders without special experiences', (
      WidgetTester tester,
    ) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(createTestWidget('boho-woven-rug'));
      await tester.pumpAndSettle();

      // Data checks
      expect(find.text('Boho Woven Rug'), findsOneWidget);

      // Actions
      expect(find.text('Try It On'), findsNothing);
      expect(find.text('View in Your Room'), findsNothing);
      expect(find.textContaining('Add to Cart'), findsOneWidget);

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });

    testWidgets('Phase 8.11a: shows the exact current stock as "N available" '
        'wired to the real product data', (tester) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = MockCommerceDatabase();
      await db.updateStock('luna-accent-chair', 6);

      await tester.pumpWidget(createTestWidget('luna-accent-chair', db: db));
      await tester.pumpAndSettle();

      expect(find.text('6 available'), findsOneWidget);
      expect(find.text('Out of Stock'), findsNothing);
      // In stock -> the CTA is a normal, enabled "Add to Cart".
      expect(find.text('Add to Cart'), findsOneWidget);
    });

    testWidgets('Phase 8.11a: stock 0 shows "Out of Stock" and disables the '
        'Add to Cart CTA', (tester) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = MockCommerceDatabase();
      await db.updateStock('luna-accent-chair', 0);

      await tester.pumpWidget(createTestWidget('luna-accent-chair', db: db));
      await tester.pumpAndSettle();

      // Stock indicator + relabelled CTA.
      expect(find.text('Out of Stock'), findsWidgets);
      expect(find.text('Add to Cart'), findsNothing);
      expect(find.text('6 available'), findsNothing);

      // The CTA button is disabled.
      final button = tester.widget<ElevatedButton>(
        find.ancestor(
          of: find.text('Out of Stock'),
          matching: find.byType(ElevatedButton),
        ),
      );
      expect(button.onPressed, isNull);
    });
  });
}
