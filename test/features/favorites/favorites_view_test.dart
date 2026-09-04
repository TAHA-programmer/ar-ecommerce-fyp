import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/app_router.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/features/favorites/views/favorites_view.dart';
import 'package:twin_ar/features/explore/widgets/explore_product_card.dart';
import 'package:twin_ar/core/widgets/states/app_empty_state.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';

void main() {
  Widget createTestWidget(
    CustomerShoppingState shoppingState,
    ProductDetailsRepository repository,
  ) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider.value(value: shoppingState),
        Provider.value(value: repository),
      ],
      child: MaterialApp(
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: const FavoritesView(),
      ),
    );
  }

  group('FavoritesView', () {
    late CustomerShoppingState shoppingState;
    late ProductDetailsRepository repository;

    setUp(() {
      shoppingState = CustomerShoppingState(
        MockFavoritesRepository(),
        MockCartRepository(),
      );
      repository = MockProductDetailsRepository(
        MockCommerceDatabase(),
        simulateDelay: false,
      );
    });

    testWidgets('renders empty state correctly', (tester) async {
      await tester.pumpWidget(createTestWidget(shoppingState, repository));
      await tester.pumpAndSettle();

      expect(find.byType(AppEmptyState), findsOneWidget);
      expect(find.text('No favorites yet'), findsOneWidget);
      expect(
        find.text('Save products you love and they’ll appear here.'),
        findsOneWidget,
      );
      expect(find.text('Explore Products'), findsOneWidget);
    });

    testWidgets('renders multiple favorite products', (tester) async {
      shoppingState.toggleFavorite('luna-3-seater-sofa');
      shoppingState.toggleFavorite('boho-woven-rug');

      await tester.pumpWidget(createTestWidget(shoppingState, repository));
      // Wait for repository fetch
      await tester.pumpAndSettle();

      expect(find.byType(ExploreProductCard), findsNWidgets(2));
      expect(find.text('Luna Right-Chaise Sectional Sofa'), findsOneWidget);
      expect(find.text('Boho Woven Rug'), findsOneWidget);
    });

    testWidgets('unfavorite removes card from UI immediately', (tester) async {
      shoppingState.toggleFavorite('luna-3-seater-sofa');

      await tester.pumpWidget(createTestWidget(shoppingState, repository));
      await tester.pumpAndSettle();

      expect(find.byType(ExploreProductCard), findsOneWidget);

      // Tap the favorite button (it's the only IconButton with favorite icon in the card)
      final favoriteBtn = find.byIcon(Icons.favorite);
      expect(favoriteBtn, findsOneWidget);
      await tester.tap(favoriteBtn);

      // We expect the state to notify listeners instantly removing it from UI
      await tester.pumpAndSettle();

      expect(find.byType(ExploreProductCard), findsNothing);
      expect(find.byType(AppEmptyState), findsOneWidget);
    });
  });
}
