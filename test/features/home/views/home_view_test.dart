import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/customer_address_state.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_address_repository.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/core/widgets/navigation/customer_bottom_navigation.dart';
import 'package:twin_ar/core/widgets/navigation/customer_header.dart';
import 'package:twin_ar/core/widgets/states/app_error_state.dart';
import 'package:twin_ar/features/address/models/address_model.dart';
import 'package:twin_ar/features/home/models/category_model.dart';
import 'package:twin_ar/features/home/models/home_banner_model.dart';
import 'package:twin_ar/features/home/repositories/home_repository.dart';
import 'package:twin_ar/features/home/repositories/mock_home_repository.dart';
import 'package:twin_ar/features/home/viewmodels/home_viewmodel.dart';
import 'package:twin_ar/features/home/views/home_view.dart';
import 'package:twin_ar/features/home/widgets/cards/vertical_product_card.dart';
import 'package:twin_ar/features/home/widgets/home_hero_carousel.dart';
import 'package:twin_ar/features/home/widgets/home_search_bar.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';

const _uid = 'test-uid';

AddressModel _address({
  String id = 'a1',
  String? label = 'Home',
  String line1 = '742 Evergreen Terrace',
  String city = 'Rawalpindi',
  bool isDefault = true,
}) => AddressModel(
  id: id,
  label: label,
  fullName: 'Wajeeha Kamran',
  phoneNumber: '03001234567',
  addressLine1: line1,
  city: city,
  provinceOrState: 'Punjab',
  postalCode: '46000',
  isDefault: isDefault,
);

/// A [HomeRepository] whose Categories read throws until [healed]. Banners
/// stay fine. The product sections do not go through the repository at all
/// now — they derive from the [CommerceDatabase] cache.
class _CategoriesFailRepository implements HomeRepository {
  bool healed = false;

  @override
  Future<List<HomeBannerModel>> getBanners() async => const [];
  @override
  Future<List<CategoryModel>> getCategories() async {
    if (!healed) throw Exception('[cloud_firestore/permission-denied]');
    return const [];
  }

  @override
  Future<List<ProductSummaryModel>> getBestSellers() async => const [];
  @override
  Future<List<ProductSummaryModel>> getFeaturedProducts() async => const [];
  @override
  Future<List<ProductSummaryModel>> getNewArrivals() async => const [];
  @override
  Future<List<ProductSummaryModel>> getArEnabledProducts() async => const [];
  @override
  Future<List<ProductSummaryModel>> getVirtualTryOnCollection() async =>
      const [];
  @override
  Future<List<ProductSummaryModel>> getPopularFurniture() async => const [];
  @override
  Future<List<ProductSummaryModel>> getRecentlyViewed() async => const [];
  @override
  Future<void> refresh() async {}
}

/// An empty catalogue — so the cache-derived Home sections have nothing to
/// show. Combined with [_CategoriesFailRepository] this is the only scenario
/// that warrants Home's full-screen error + Retry.
class _EmptyCommerceDatabase extends CommerceDatabase {
  @override
  List<ProductModel> get products => const [];
  @override
  List<OrderModel> get orders => const [];
  @override
  List<PaymentRecord> get payments => const [];
  @override
  ProductModel getProductById(String id) => throw StateError('empty');
  @override
  Future<void> addProduct(ProductModel product) async {}
  @override
  Future<void> updateProduct(ProductModel product) async {}
  @override
  Future<void> setProductActive(String productId, bool isActive) async {}
  @override
  Future<void> updateStock(String productId, int newStockQuantity) async {}
  @override
  Future<void> deleteProduct(String productId) async {}
  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {}
}

void main() {
  Future<Widget> createTestWidget({
    ValueChanged<RouteSettings>? onRoutePushed,
    List<AddressModel>? addresses,
    bool addressesLoading = false,
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

    final addressRepo = MockAddressRepository(
      initialAddresses: addresses ?? const [],
    );
    if (addressesLoading) addressRepo.simulateLoading();
    final addressState = CustomerAddressState(addressRepo);

    return MaterialApp(
      onGenerateRoute: (settings) {
        if (settings.name != '/') {
          onRoutePushed?.call(settings);
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
          ChangeNotifierProvider<CustomerAddressState>.value(
            value: addressState,
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
      await tester.pump(const Duration(seconds: 1));
    });

    testWidgets('renders the dynamic home sections after data loads', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(CustomerHeader), findsOneWidget);
      expect(
        find.textContaining('Wajeeha', findRichText: true),
        findsOneWidget,
      );
      expect(find.byType(HomeSearchBar), findsOneWidget);
      expect(find.byType(HomeHeroCarousel), findsOneWidget);
      expect(find.text('Shop by Category'), findsOneWidget);

      final scrollable = find.byType(Scrollable).first;
      for (final title in const [
        'Top Rated',
        'Featured Products',
        'New Arrivals',
        'AR Enabled Products',
        'Virtual Try-On Collection',
        'Top Rated Furniture & Decor',
      ]) {
        await tester.scrollUntilVisible(
          find.text(title),
          200,
          scrollable: scrollable,
        );
        expect(find.text(title), findsOneWidget, reason: title);
      }

      // Removed until its real per-customer contract ships (Stage 2/3).
      expect(find.text('Recently Viewed'), findsNothing);
      // Never a fabricated-sales / fabricated-popularity label.
      expect(find.text('Best Sellers'), findsNothing);
      expect(find.text('Popular Furniture & Decor'), findsNothing);

      expect(find.byType(CustomerBottomNavigation), findsOneWidget);
    });

    testWidgets('delivery-address row shows the default address and is '
        'tappable to Saved Addresses', (tester) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RouteSettings? pushed;
      await tester.pumpWidget(
        await createTestWidget(
          onRoutePushed: (s) => pushed = s,
          addresses: [_address(line1: '742 Evergreen Terrace')],
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Deliver to'), findsOneWidget);
      expect(find.textContaining('742 Evergreen Terrace'), findsOneWidget);
      // The old hardcoded value and its down-arrow are gone.
      expect(find.text('Adiala Road, Rawalpindi'), findsNothing);
      expect(find.byIcon(Icons.keyboard_arrow_down), findsNothing);

      await tester.tap(find.textContaining('Deliver to'));
      await tester.pumpAndSettle();
      expect(pushed?.name, RouteNames.savedAddresses);
    });

    testWidgets('delivery-address row is hidden (icon included) when there is '
        'no default address', (tester) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(await createTestWidget(addresses: const []));
      await tester.pumpAndSettle();

      expect(find.textContaining('Deliver to'), findsNothing);
      expect(find.byIcon(Icons.location_on), findsNothing);
      // Product sections still render — address absence never blanks them.
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('New Arrivals'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('New Arrivals'), findsOneWidget);
    });

    testWidgets('delivery-address row is hidden while the address state is '
        'still loading', (tester) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      await tester.pumpWidget(
        await createTestWidget(addresses: [_address()], addressesLoading: true),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Deliver to'), findsNothing);
    });

    testWidgets('a Categories failure shows an inline retry strip WITHOUT '
        'blanking the product sections', (tester) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _CategoriesFailRepository();
      final db = MockCommerceDatabase(); // real catalogue → product sections OK
      final profileState = CustomerProfileState(
        MockUserProfileRepository(seed: const {}),
      );
      final addressState = CustomerAddressState(MockAddressRepository());

      await tester.pumpWidget(
        MaterialApp(
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
              ChangeNotifierProvider<CustomerAddressState>.value(
                value: addressState,
              ),
              ChangeNotifierProvider(
                create: (context) => HomeViewModel(
                  repo,
                  MockProductDetailsRepository(db, simulateDelay: false),
                  context.read<CustomerShoppingState>(),
                  db,
                ),
              ),
            ],
            child: const HomeView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // No full-screen error — Home has plenty of content.
      expect(find.byType(AppErrorState), findsNothing);
      // Inline category retry strip present.
      expect(find.text("Couldn't load categories."), findsOneWidget);
      final scrollable = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('New Arrivals'),
        200,
        scrollable: scrollable,
      );
      expect(find.text('New Arrivals'), findsOneWidget);
    });

    testWidgets('full-screen error + Retry only when Categories fail AND the '
        'catalogue is empty; recovers on Retry', (tester) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final repo = _CategoriesFailRepository();
      final db = _EmptyCommerceDatabase();
      final profileState = CustomerProfileState(
        MockUserProfileRepository(seed: const {}),
      );
      final addressState = CustomerAddressState(MockAddressRepository());

      await tester.pumpWidget(
        MaterialApp(
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
              ChangeNotifierProvider<CustomerAddressState>.value(
                value: addressState,
              ),
              ChangeNotifierProvider(
                create: (context) => HomeViewModel(
                  repo,
                  MockProductDetailsRepository(
                    MockCommerceDatabase(),
                    simulateDelay: false,
                  ),
                  context.read<CustomerShoppingState>(),
                  db,
                ),
              ),
            ],
            child: const HomeView(),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(AppErrorState), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);

      repo.healed = true;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();
      expect(find.byType(AppErrorState), findsNothing);
    });

    testWidgets('tapping a product card pushes product details', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(1290, 2796);
      tester.view.devicePixelRatio = 3.0;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      RouteSettings? pushedRoute;
      await tester.pumpWidget(
        await createTestWidget(onRoutePushed: (s) => pushedRoute = s),
      );
      await tester.pumpAndSettle();

      final card = find.byType(VerticalProductCard).first;
      await tester.scrollUntilVisible(
        card,
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(card);
      await tester.pumpAndSettle();

      expect(pushedRoute?.name, RouteNames.productDetails);
      expect(pushedRoute!.arguments, isA<String>());
    });
  });
}
