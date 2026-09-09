import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/widgets/states/app_empty_state.dart';
import 'package:twin_ar/features/home/widgets/cards/wide_product_card.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_recently_viewed_repository.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/features/product_details/repositories/recently_viewed_repository.dart';
import 'package:twin_ar/features/recently_viewed/views/recently_viewed_view.dart';

void main() {
  Widget wrap(
    MockRecentlyViewedRepository rv, {
    ValueChanged<RouteSettings>? onPush,
  }) {
    final db = MockCommerceDatabase();
    return MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name != '/') {
          onPush?.call(settings);
          return MaterialPageRoute(
            builder: (_) => Scaffold(body: Text('route: ${settings.name}')),
          );
        }
        return null;
      },
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<CommerceDatabase>.value(value: db),
          Provider<RecentlyViewedRepository>.value(value: rv),
          Provider<ProductDetailsRepository>.value(
            value: MockProductDetailsRepository(db, simulateDelay: false),
          ),
          ChangeNotifierProvider(
            create: (_) => CustomerShoppingState(
              MockFavoritesRepository(),
              MockCartRepository(),
            ),
          ),
        ],
        child: const RecentlyViewedView(),
      ),
    );
  }

  testWidgets('empty history shows the empty state', (tester) async {
    await tester.pumpWidget(
      wrap(MockRecentlyViewedRepository(signedIn: false)),
    );
    await tester.pumpAndSettle();

    expect(find.text('Recently Viewed'), findsOneWidget); // header
    expect(find.byType(AppEmptyState), findsOneWidget);
  });

  testWidgets('renders the history newest-first as product cards', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = MockCommerceDatabase();
    final ids = db.products.take(4).map((p) => p.id).toList();
    final rv = MockRecentlyViewedRepository();
    for (final id in ids) {
      await rv.recordView(id);
    }

    await tester.pumpWidget(wrap(rv));
    await tester.pumpAndSettle();

    expect(find.byType(AppEmptyState), findsNothing);
    expect(find.byType(WideProductCard), findsWidgets);
  });

  testWidgets('tapping a card navigates to product details', (tester) async {
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final db = MockCommerceDatabase();
    final id = db.products.first.id;
    final rv = MockRecentlyViewedRepository()..recordView(id);

    RouteSettings? pushed;
    await tester.pumpWidget(wrap(rv, onPush: (s) => pushed = s));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(WideProductCard).first);
    await tester.pumpAndSettle();

    expect(pushed?.name, RouteNames.productDetails);
    expect(pushed?.arguments, id);
  });
}
