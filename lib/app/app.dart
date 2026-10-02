import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'app_providers.dart';
import 'routes/app_router.dart';
import 'routes/route_names.dart';
import '../core/data/category_repository.dart';
import '../core/data/commerce_database.dart';
import '../core/data/address_repository.dart';
import '../core/data/favorites_repository.dart';
import '../core/data/cart_repository.dart';
import '../features/checkout/services/checkout_payment_service.dart';
import '../core/theme/app_theme.dart';
import '../features/auth/repositories/auth_repository.dart';
import '../features/notifications/services/notification_route_tracker.dart';
import '../features/notifications/widgets/notification_host.dart';
import '../features/profile/repositories/user_profile_repository.dart';

class TWinArApp extends StatelessWidget {
  /// Test-only injection seams - see [AppProviders.providers]. Never passed
  /// in production, so [AppProviders] always wires the real
  /// [FirebaseAuthRepository]/[FirestoreUserProfileRepository]/
  /// [FirestoreCommerceDatabase]/[FirestoreCategoryRepository]/
  /// [FirestoreAddressRepository]/[FirestoreFavoritesRepository]/
  /// [FirestoreCartRepository].
  final AuthRepository? authRepositoryOverride;
  final UserProfileRepository? userProfileRepositoryOverride;
  final CommerceDatabase? commerceDatabaseOverride;
  final CategoryRepository? categoryRepositoryOverride;
  final AddressRepository? addressRepositoryOverride;
  final FavoritesRepository? favoritesRepositoryOverride;
  final CartRepository? cartRepositoryOverride;
  final CheckoutPaymentService? checkoutPaymentServiceOverride;

  /// FCM notifications (Stage S5): when true the app starts the notification
  /// lifecycle (device registration, tap routing, foreground banner). Only the
  /// production `main.dart` passes true; widget tests leave it false so they
  /// never touch FirebaseMessaging.
  final bool enableNotifications;

  const TWinArApp({
    super.key,
    this.authRepositoryOverride,
    this.userProfileRepositoryOverride,
    this.commerceDatabaseOverride,
    this.categoryRepositoryOverride,
    this.addressRepositoryOverride,
    this.favoritesRepositoryOverride,
    this.cartRepositoryOverride,
    this.checkoutPaymentServiceOverride,
    this.enableNotifications = false,
  });

  @override
  Widget build(BuildContext context) {
    Widget app = MaterialApp(
      title: 'TWin AR',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme,
      // The app is Light Theme only
      themeMode: ThemeMode.light,
      initialRoute: RouteNames.splash,
      onGenerateRoute: AppRouter.onGenerateRoute,
      navigatorKey: AppRouter.navigatorKey,
      navigatorObservers: [
        AppRouter.routeObserver,
        NotificationRouteTracker.instance,
      ],
      builder: enableNotifications
          ? (context, child) =>
                NotificationHost(child: child ?? const SizedBox.shrink())
          : null,
    );

    final providers = AppProviders.providers(
      authRepository: authRepositoryOverride,
      userProfileRepository: userProfileRepositoryOverride,
      commerceDatabase: commerceDatabaseOverride,
      categoryRepository: categoryRepositoryOverride,
      addressRepository: addressRepositoryOverride,
      favoritesRepository: favoritesRepositoryOverride,
      cartRepository: cartRepositoryOverride,
      checkoutPaymentService: checkoutPaymentServiceOverride,
    );
    if (providers.isNotEmpty) {
      return MultiProvider(providers: providers, child: app);
    }

    return app;
  }
}
