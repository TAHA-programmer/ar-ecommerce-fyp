import 'package:flutter/material.dart';
import 'package:twin_ar/core/constants/delivery_constants.dart';
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
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/features/reviews/repositories/reviews_repository.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';

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
          // Ratings/Reviews v1 Stage 6 — ProductDetailsView now also
          // constructs a ReviewsViewModel alongside ProductDetailsViewModel.
          ChangeNotifierProvider<AuthSessionState>(
            create: (_) => AuthSessionState(),
          ),
          Provider<ReviewsRepository>(create: (_) => MockReviewsRepository()),
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

      // Favorite and cart (live badge, opens Cart) in header — share was
      // replaced with the same functional cart icon as the main app bar.
      // Scoped to the AppBar since "Add to Cart" also uses a cart icon.
      expect(find.byIcon(Icons.favorite_border), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(AppBar),
          matching: find.byIcon(Icons.shopping_cart_outlined),
        ),
        findsOneWidget,
      );
      expect(find.byIcon(Icons.share_outlined), findsNothing);

      // NO CustomerBottomNavigation
      expect(find.byType(CustomerBottomNavigation), findsNothing);

      // Data checks
      expect(find.text('Luna Accent Chair'), findsOneWidget);
      expect(find.text('Rs 12,000/-'), findsOneWidget);
      expect(find.text('Rs 16,000/-'), findsOneWidget);
      expect(find.text('25% OFF'), findsOneWidget);

      // Dynamic category breadcrumb (a RichText, hence findRichText: true),
      // sourced from real product data.
      expect(
        find.textContaining('Furniture', findRichText: true),
        findsWidgets,
      );
      expect(
        find.textContaining('Accent Chairs', findRichText: true),
        findsOneWidget,
      );

      // Specifications
      expect(find.text('Material'), findsOneWidget);
      expect(find.text('Premium Fabric, Solid Wood'), findsOneWidget);
      expect(find.text('Dimensions'), findsOneWidget);

      // Delivery card now reads the centralized, truthful delivery policy —
      // never a per-product hardcoded date.
      expect(
        find.text(DeliveryConstants.estimatedDeliveryLabel),
        findsOneWidget,
      );
      expect(find.text(DeliveryConstants.deliveryFeeLabel), findsOneWidget);
      expect(find.textContaining('20 - 24 May'), findsNothing);

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

      // Dynamic category breadcrumb (a RichText, hence findRichText: true),
      // sourced from real product data.
      expect(find.textContaining('Clothing', findRichText: true), findsWidgets);
      expect(find.textContaining('Shirts', findRichText: true), findsOneWidget);

      // Fabric/Fit/Care rows are informational, not navigation — no
      // trailing chevrons.
      expect(find.byIcon(Icons.chevron_right), findsNothing);

      // Sizes
      expect(find.text('S'), findsOneWidget);
      expect(find.text('M'), findsOneWidget);
      expect(find.text('L'), findsOneWidget);
      expect(find.text('XL'), findsOneWidget);
      expect(find.text('XXL'), findsOneWidget);

      // Benefits — the delivery-fee item reflects the real flat fee, never
      // a fictional "free above Rs X" claim.
      expect(find.textContaining('7-Day Easy'), findsOneWidget);
      expect(find.textContaining('Secure'), findsOneWidget);
      expect(
        find.textContaining(DeliveryConstants.deliveryFeeLabel),
        findsOneWidget,
      );
      expect(find.textContaining('Free Shipping'), findsNothing);

      // Actions — Phase 9.3 Stage 5: "Try It On" is now gated on
      // `hasRenderableVtoAsset`, not `experienceType` alone. The mock
      // catalogue deliberately carries no VTO garment contract for ANY seed
      // product yet (see `product_model_vto_test.dart`'s "existing catalogue
      // is undisturbed" regression test), so this virtualTryOn-enabled
      // product is correctly NOT yet launchable — exactly the same honest
      // "no dead button" treatment as an unconfigured Room AR product.
      expect(find.text('Try It On'), findsNothing);
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
