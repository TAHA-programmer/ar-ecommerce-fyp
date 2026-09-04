import 'package:provider/single_child_widget.dart';
import 'package:provider/provider.dart';
import '../core/data/commerce_database.dart';
import '../core/data/firestore_commerce_database.dart';
import '../core/data/category_repository.dart';
import '../core/data/firestore_category_repository.dart';
import '../core/data/address_repository.dart';
import '../core/data/firestore_address_repository.dart';
import '../core/data/favorites_repository.dart';
import '../core/data/firestore_favorites_repository.dart';
import '../core/data/cart_repository.dart';
import '../core/data/firestore_cart_repository.dart';
import 'viewmodels/customer_shopping_state.dart';
import 'viewmodels/customer_address_state.dart';
import 'viewmodels/customer_order_state.dart';
import '../features/home/repositories/home_repository.dart';
import '../features/home/repositories/firestore_home_repository.dart';
import '../features/home/viewmodels/home_viewmodel.dart';
import '../features/explore/repositories/explore_repository.dart';
import '../features/explore/repositories/firestore_explore_repository.dart';
import '../features/explore/viewmodels/explore_viewmodel.dart';
import '../features/auth/repositories/auth_repository.dart';
import '../features/auth/repositories/firebase_auth_repository.dart';
import '../features/profile/repositories/user_profile_repository.dart';
import '../features/profile/repositories/firestore_user_profile_repository.dart';
import '../core/services/storage_service.dart';
import '../core/services/firebase_storage_service.dart';
import 'viewmodels/auth_session_state.dart';
import 'viewmodels/customer_profile_state.dart';

import '../features/product_details/repositories/product_details_repository.dart';
import '../features/product_details/repositories/firestore_product_details_repository.dart';
import '../features/room_ar/capability/room_ar_capability_service.dart';
import '../features/checkout/services/checkout_payment_service.dart';
import '../features/checkout/services/stripe_checkout_payment_service.dart';
import '../features/checkout/services/checkout_cart_reconciler.dart';
import '../features/admin/dashboard/viewmodels/admin_dashboard_viewmodel.dart';

class AppProviders {
  AppProviders._();

  /// [authRepository]/[userProfileRepository]/[commerceDatabase]/
  /// [categoryRepository]/[addressRepository]/[favoritesRepository]/
  /// [cartRepository] are optional test-only injection seams - production
  /// callers never pass them, so the app always gets the real
  /// Firebase-backed implementations. They exist so widget tests that pump
  /// the real [TWinArApp] tree (e.g. `test/widget_test.dart`) can substitute
  /// mocks without needing a real Firebase backend.
  static List<SingleChildWidget> providers({
    AuthRepository? authRepository,
    UserProfileRepository? userProfileRepository,
    CommerceDatabase? commerceDatabase,
    StorageService? storageService,
    CategoryRepository? categoryRepository,
    AddressRepository? addressRepository,
    FavoritesRepository? favoritesRepository,
    CartRepository? cartRepository,
    CheckoutPaymentService? checkoutPaymentService,
  }) => [
    // AuthRepository/AuthSessionState are registered before
    // CommerceDatabase because FirestoreCommerceDatabase (Phase 8.5) needs
    // AuthSessionState to know whether to run its admin (unfiltered) or
    // customer (published+active) product query - see
    // FirestoreCommerceDatabase's doc comment for why.
    Provider<AuthRepository>(
      create: (_) => authRepository ?? FirebaseAuthRepository(),
    ),
    ChangeNotifierProxyProvider<AuthRepository, AuthSessionState>(
      create: (context) => AuthSessionState(context.read<AuthRepository>()),
      update: (_, repo, previous) => previous ?? AuthSessionState(repo),
    ),
    ChangeNotifierProxyProvider<AuthSessionState, CommerceDatabase>(
      create: (context) =>
          commerceDatabase ??
          FirestoreCommerceDatabase(context.read<AuthSessionState>()),
      update: (_, authState, previous) =>
          previous ?? commerceDatabase ?? FirestoreCommerceDatabase(authState),
    ),
    // Same role-aware reactive pattern as CommerceDatabase above - see
    // FirestoreCategoryRepository's doc comment.
    ChangeNotifierProxyProvider<AuthSessionState, CategoryRepository>(
      create: (context) =>
          categoryRepository ??
          FirestoreCategoryRepository(context.read<AuthSessionState>()),
      update: (_, authState, previous) =>
          previous ??
          categoryRepository ??
          FirestoreCategoryRepository(authState),
    ),
    // Phase 8.10: addresses/favorites/cart are owner-scoped (uid, not role)
    // - each repository self-manages its own uid-keyed live subscription
    // from AuthSessionState, mirroring CategoryRepository's role-aware
    // pattern above. See FirestoreAddressRepository's doc comment for the
    // full uid-isolation/generation-guard design shared by all three.
    ChangeNotifierProxyProvider<AuthSessionState, AddressRepository>(
      create: (context) =>
          addressRepository ??
          FirestoreAddressRepository(context.read<AuthSessionState>()),
      update: (_, authState, previous) =>
          previous ??
          addressRepository ??
          FirestoreAddressRepository(authState),
    ),
    ChangeNotifierProxyProvider<AuthSessionState, FavoritesRepository>(
      create: (context) =>
          favoritesRepository ??
          FirestoreFavoritesRepository(context.read<AuthSessionState>()),
      update: (_, authState, previous) =>
          previous ??
          favoritesRepository ??
          FirestoreFavoritesRepository(authState),
    ),
    ChangeNotifierProxyProvider<AuthSessionState, CartRepository>(
      create: (context) =>
          cartRepository ??
          FirestoreCartRepository(context.read<AuthSessionState>()),
      update: (_, authState, previous) =>
          previous ?? cartRepository ?? FirestoreCartRepository(authState),
    ),
    Provider<UserProfileRepository>(
      create: (_) => userProfileRepository ?? FirestoreUserProfileRepository(),
    ),
    Provider<StorageService>(
      create: (_) => storageService ?? FirebaseStorageService(),
    ),
    // Home/Explore/Product Details no longer depend on CommerceDatabase -
    // their Firestore implementations query Firestore directly (see each
    // file's doc comment for why: they're one-shot Future-based reads, not
    // reactive getters, so they don't need the role-aware live cache
    // CommerceDatabase maintains for Admin/Checkout).
    Provider<ProductDetailsRepository>(
      create: (_) => FirestoreProductDetailsRepository(),
    ),
    // Phase 9.2 R8 — Room-AR device-capability probe for tier routing. Leaf
    // infra (a native method channel + permission_handler); no dependencies.
    Provider<RoomArCapabilityService>(
      create: (_) => DefaultRoomArCapabilityService(),
    ),
    // Phase 8.13.5: the Stripe checkout seam (createPaymentIntent callable +
    // PaymentSheet + checkoutSessions listener). Optional test-injection seam,
    // like the repositories above.
    Provider<CheckoutPaymentService>(
      create: (_) => checkoutPaymentService ?? StripeCheckoutPaymentService(),
    ),
    Provider<HomeRepository>(create: (_) => FirestoreHomeRepository()),
    Provider<ExploreRepository>(create: (_) => FirestoreExploreRepository()),
    ChangeNotifierProxyProvider2<
      FavoritesRepository,
      CartRepository,
      CustomerShoppingState
    >(
      create: (context) => CustomerShoppingState(
        context.read<FavoritesRepository>(),
        context.read<CartRepository>(),
      ),
      update: (_, favorites, cart, previous) =>
          previous ?? CustomerShoppingState(favorites, cart),
    ),
    // Phase 8.13.6 - late-success cart reconciliation. Eager (`lazy: false`)
    // so it starts observing sign-in / app-resume immediately; nothing reads
    // it as a dependency. Only reads `checkoutSessions` + mutates the cart.
    Provider<CheckoutCartReconciler>(
      lazy: false,
      create: (context) => CheckoutCartReconciler(
        context.read<CheckoutPaymentService>(),
        context.read<CustomerShoppingState>(),
        context.read<AuthSessionState>(),
      ),
      dispose: (_, reconciler) => reconciler.dispose(),
    ),
    ChangeNotifierProxyProvider<AddressRepository, CustomerAddressState>(
      create: (context) =>
          CustomerAddressState(context.read<AddressRepository>()),
      update: (_, repository, previous) =>
          previous ?? CustomerAddressState(repository),
    ),
    ChangeNotifierProxyProvider<CommerceDatabase, CustomerOrderState>(
      create: (context) => CustomerOrderState(context.read<CommerceDatabase>()),
      update: (_, db, previous) => previous ?? CustomerOrderState(db),
    ),
    ChangeNotifierProxyProvider3<
      AuthSessionState,
      UserProfileRepository,
      StorageService,
      CustomerProfileState
    >(
      create: (context) => CustomerProfileState(
        context.read<UserProfileRepository>(),
        storageService: context.read<StorageService>(),
      ),
      update: (_, authState, repository, storage, previous) {
        final state =
            previous ??
            CustomerProfileState(repository, storageService: storage);
        // Fire-and-forget: loadForUser is idempotent per uid (see its
        // doc comment), so calling it on every AuthSessionState change
        // - not just login/logout - is safe and simply no-ops once
        // already loaded for the current user.
        state.loadForUser(authState.userId);
        return state;
      },
    ),
    ChangeNotifierProvider(
      create: (context) => HomeViewModel(
        context.read<HomeRepository>(),
        context.read<ProductDetailsRepository>(),
        context.read<CustomerShoppingState>(),
        context.read<CommerceDatabase>(),
      ),
    ),
    ChangeNotifierProvider(
      create: (context) => ExploreViewModel(
        context.read<ExploreRepository>(),
        context.read<ProductDetailsRepository>(),
        context.read<CustomerShoppingState>(),
        context.read<CommerceDatabase>(),
        context.read<CategoryRepository>(),
      ),
    ),
    ChangeNotifierProxyProvider<CommerceDatabase, AdminDashboardViewModel>(
      create: (context) =>
          AdminDashboardViewModel(context.read<CommerceDatabase>()),
      update: (_, db, previous) => previous ?? AdminDashboardViewModel(db),
    ),
  ];
}
