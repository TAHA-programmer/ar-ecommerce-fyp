import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/features/home/repositories/mock_home_repository.dart';
import 'package:twin_ar/features/home/viewmodels/home_viewmodel.dart';
import 'package:twin_ar/features/home/views/home_view.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/widgets/navigation/customer_header.dart';
import 'package:twin_ar/features/home/widgets/home_search_bar.dart';
import 'package:twin_ar/features/home/widgets/home_hero_carousel.dart';
import 'package:twin_ar/core/widgets/navigation/customer_bottom_navigation.dart';
import 'package:twin_ar/features/home/widgets/cards/vertical_product_card.dart';

const _uid = 'test-uid';

void main() {
  Future<Widget> createTestWidget({
    ValueChanged<RouteSettings>? onRoutePushed,
  }) async {
    final db = MockCommerceDatabase();
    final profileRepository = MockUserProfileRepository(
      seed: {
        _uid: const UserProfileModel(
          uid: _uid,
          email: 'wajeeha.kamran@example.com',
          displayName: 'Wajeeha Kamran',
          phone: '+92 300 0000000',
          role: 'customer',
        ),
      },
    );
    final profileState = CustomerProfileState(profileRepository);
    await profileState.loadForUser(_uid);

    return MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name != '/') {
          if (onRoutePushed != null) {
            onRoutePushed(settings);
          }
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
          ChangeNotifierProvider<CustomerProfileState>.value(
            value: profileState,
          ),
          ChangeNotifierProvider(
            create: (context) => HomeViewModel(
              MockHomeRepository(db),
              MockProductDetailsRepository(db, simulateDelay: false),
              context.read<CustomerShoppingState>(),
              db,
            ),
          ),
        ],
        child: const HomeView(),
      ),
    );
  }

  group('HomeView Widget Tests', () {
    testWidgets('renders loading state initially', (WidgetTester tester) async {
      await tester.pumpWidget(await createTestWidget());
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.pump(
        const Duration(seconds: 1),
      ); // allow mock timers to clear
      // Removed pumpAndSettle here because CircularProgressIndicator animates indefinitely
    });

    testWidgets('renders home view sections after data loads', (
      WidgetTester tester,
    ) async {
      // Setup a realistic mobile size for the test
      tester.view.physicalSize = const Size(
        1290,
        2796,
      ); // iPhone 14 Pro Max size roughly (scale 3.0)
      tester.view.devicePixelRatio = 3.0;

      await tester.pumpWidget(await createTestWidget());

      // Allow data to load (since it has delays in the mock)
      await tester.pumpAndSettle();

      // Verify Header
      expect(find.byType(CustomerHeader), findsOneWidget);

      // Greeting shows the real signed-in user's first name, not a
      // hardcoded placeholder. The greeting is a raw RichText, not a Text
      // widget, so the finder needs findRichText: true to see into it.
      expect(
        find.textContaining('Wajeeha', findRichText: true),
        findsOneWidget,
      );

      // Verify Search Bar
      expect(find.byType(HomeSearchBar), findsOneWidget);

      // Verify Hero Carousel
      expect(find.byType(HomeHeroCarousel), findsOneWidget);

      // Verify Section titles
      expect(find.text('Shop by Category'), findsOneWidget);
      expect(find.text('Best Sellers'), findsOneWidget);

      final scrollable = find.byType(Scrollable).first;

      await tester.scrollUntilVisible(
        find.text('Featured Products'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Featured Products'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('New Arrivals'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('New Arrivals'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('AR Enabled Products'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('AR Enabled Products'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Virtual Try-On Collection'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Virtual Try-On Collection'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Popular Furniture & Decor'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Popular Furniture & Decor'), findsOneWidget);

      await tester.scrollUntilVisible(
        find.text('Recently Viewed'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('Recently Viewed'), findsOneWidget);
      // Verify Bottom Navigation
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
        await createTestWidget(
          onRoutePushed: (settings) {
            pushedRoute = settings;
          },
        ),
      );
      await tester.pumpAndSettle();

      // Find a product card
      final cardFinder = find.byType(VerticalProductCard).first;
      await tester.scrollUntilVisible(
        cardFinder,
        200,
        scrollable: find.byType(Scrollable).first,
      );

      await tester.tap(cardFinder);
      await tester.pumpAndSettle();

      // Verify the correct route is pushed
      expect(pushedRoute, isNotNull);
      expect(pushedRoute!.name, '/product-details');
      expect(pushedRoute!.arguments, isA<String>());

      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    });
  });
}
