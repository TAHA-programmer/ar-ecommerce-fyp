import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'route_names.dart';
import '../../core/theme/app_typography.dart';
import '../../core/theme/app_colors.dart';
import '../../features/splash/viewmodels/splash_viewmodel.dart';
import '../../features/splash/views/splash_view.dart';
import '../../app/routes/explore_launch_intent.dart';
import '../../core/data/commerce_database.dart';
import '../../core/services/storage_service.dart';

import '../../features/onboarding/viewmodels/onboarding_viewmodel.dart';
import '../../features/onboarding/views/onboarding_view.dart';
import '../../features/auth/login/viewmodels/login_viewmodel.dart';
import '../../features/auth/login/views/login_view.dart';
import '../../features/auth/repositories/auth_repository.dart';
import '../../app/viewmodels/auth_session_state.dart';
import '../../features/auth/signup/viewmodels/signup_viewmodel.dart';
import '../../features/auth/signup/views/signup_view.dart';
import '../../features/auth/forgot_password/viewmodels/forgot_password_viewmodel.dart';
import '../../features/auth/forgot_password/views/forgot_password_view.dart';
import '../../features/legal/terms/views/terms_view.dart';
import '../../features/legal/privacy/views/privacy_policy_view.dart';
import '../../features/home/views/home_view.dart';
import '../../features/explore/views/explore_view.dart';
import '../../features/product_details/views/product_details_view.dart';
import '../../features/room_ar/viewmodels/room_ar_preparation_viewmodel.dart';
import '../../features/room_ar/views/room_ar_preparation_view.dart';
import '../../features/room_ar/marker_ar/viewmodels/marker_ar_viewmodel.dart';
import '../../features/room_ar/marker_ar/views/marker_ar_view.dart';
import '../../features/room_ar/marker_ar/models/marker_ar_object.dart';
import '../../features/room_ar/marker_ar/room_ar_session_args.dart';
import '../../features/room_ar/preview/room_ar_preview_view.dart';
import '../../features/room_ar/preview/room_ar_preview_viewmodel.dart';
import '../../features/room_ar/model_delivery/room_ar_model_service_factory.dart';
import '../../features/room_ar/tier1_arcore/viewmodels/room_arcore_viewmodel.dart';
import '../../features/room_ar/tier1_arcore/views/room_arcore_view.dart';
import '../../features/virtual_try_on/viewmodels/virtual_try_on_setup_viewmodel.dart';
import '../../features/virtual_try_on/views/virtual_try_on_setup_view.dart';
import '../../features/cart/viewmodels/cart_viewmodel.dart';
import '../../features/cart/views/shopping_cart_view.dart';
import '../../features/checkout/views/checkout_payment_view.dart';
import '../../features/checkout/viewmodels/checkout_viewmodel.dart';
import '../../features/checkout/services/checkout_payment_service.dart';
import '../../features/checkout/views/order_result_view.dart';
import '../../features/address/views/delivery_address_view.dart';
import '../../features/address/views/address_form_view.dart';
import '../../features/address/views/saved_addresses_view.dart';
import '../../features/favorites/views/favorites_view.dart';
import '../../features/recently_viewed/views/recently_viewed_view.dart';
import '../../features/product_details/repositories/product_details_repository.dart';
import '../../app/viewmodels/customer_shopping_state.dart';
import '../../app/viewmodels/customer_address_state.dart';
import '../../app/viewmodels/customer_order_state.dart';
import '../../features/profile/views/help_support_view.dart';
import '../../features/profile/views/room_ar_info_view.dart';
import '../../features/profile/views/virtual_try_on_info_view.dart';
import '../../features/profile/views/about_twin_ar_view.dart';
import '../../features/profile/views/edit_profile_view.dart';
import '../../features/profile/viewmodels/edit_profile_viewmodel.dart';
import '../../features/profile/views/profile_view.dart';
import '../../app/viewmodels/customer_profile_state.dart';
import '../../features/orders/views/my_orders_view.dart';
import '../../features/orders/viewmodels/my_orders_viewmodel.dart';
import '../../features/orders/views/order_detail_view.dart';
import '../../features/orders/viewmodels/order_detail_viewmodel.dart';
import '../../features/admin/views/admin_dashboard_view.dart';
import '../../features/admin/views/admin_products_view.dart';
import '../../features/admin/views/admin_inventory_view.dart';
import '../../features/admin/views/admin_orders_view.dart';

import '../../features/admin/product_management/views/admin_product_form_view.dart';
import '../../features/admin/product_management/views/admin_category_form_view.dart';
import '../../features/admin/ar_media_management/viewmodels/ar_media_management_viewmodel.dart';
import '../../features/admin/ar_media_management/viewmodels/admin_ar_model_preview_viewmodel.dart';
import '../../features/admin/ar_media_management/views/admin_ar_media_management_view.dart';
import '../../features/admin/ar_media_management/views/admin_ar_model_preview_view.dart';
import '../../features/admin/orders_payments/viewmodels/admin_order_detail_viewmodel.dart';
import '../../features/admin/orders_payments/views/admin_order_detail_view.dart';

class AppRouter {
  AppRouter._();

  /// App-wide navigation observer. `HomeView` subscribes to it so that
  /// returning to Home from a pushed screen (e.g. Product Details) refreshes
  /// the view-history / stats rails — a product the customer just opened
  /// then shows up in "Recently Viewed" without a manual pull-to-refresh.
  static final RouteObserver<PageRoute<dynamic>> routeObserver =
      RouteObserver<PageRoute<dynamic>>();

  static Route<dynamic> onGenerateRoute(RouteSettings settings) {
    switch (settings.name) {
      case RouteNames.splash:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (context) =>
                SplashViewModel(context.read<AuthSessionState>())..initialize(),
            child: const SplashView(),
          ),
        );
      case RouteNames.onboarding:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (_) => OnboardingViewModel(),
            child: const OnboardingView(),
          ),
        );
      case RouteNames.login:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (context) => LoginViewModel(
              context.read<AuthRepository>(),
              context.read<AuthSessionState>(),
            ),
            child: const LoginView(),
          ),
        );
      case RouteNames.signUp:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (context) =>
                SignupViewModel(context.read<AuthRepository>()),
            child: const SignupView(),
          ),
        );
      case RouteNames.forgotPassword:
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (context) =>
                ForgotPasswordViewModel(context.read<AuthRepository>()),
            child: const ForgotPasswordView(),
          ),
        );
      case RouteNames.terms:
        return MaterialPageRoute(builder: (_) => const TermsView());
      case RouteNames.privacy:
        return MaterialPageRoute(builder: (_) => const PrivacyPolicyView());
      case RouteNames.profile:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const ProfileView(),
        );
      case RouteNames.editProfile:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (context) =>
                EditProfileViewModel(context.read<CustomerProfileState>()),
            child: const EditProfileView(),
          ),
        );
      case RouteNames.helpSupport:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const HelpSupportView(),
        );
      case RouteNames.roomArInfo:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const RoomArInfoView(),
        );
      case RouteNames.virtualTryOnInfo:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const VirtualTryOnInfoView(),
        );
      case RouteNames.aboutTwinAr:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AboutTwinArView(),
        );
      case RouteNames.home:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const HomeView(),
        );
      case RouteNames.explore:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) =>
              ExploreView(intent: settings.arguments as ExploreLaunchIntent?),
        );
      case RouteNames.checkout:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (context) => CheckoutViewModel(
              context.read<CustomerShoppingState>(),
              context.read<CustomerAddressState>(),
              context.read<ProductDetailsRepository>(),
              context.read<AuthSessionState>(),
              context.read<CheckoutPaymentService>(),
              context.read<CustomerOrderState>(),
            ),
            child: const CheckoutPaymentView(),
          ),
        );
      case RouteNames.orderResult:
        final orderId = settings.arguments as String?;
        if (orderId == null) return _errorRoute('Order ID is required');
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => OrderResultView(orderId: orderId),
        );
      case RouteNames.productDetails:
        final productId = settings.arguments as String?;
        if (productId == null) return _errorRoute('Product ID is required');
        return MaterialPageRoute(
          builder: (_) => ProductDetailsView(productId: productId),
        );
      case RouteNames.roomArPreparation:
        final productId = settings.arguments as String?;
        if (productId == null) return _errorRoute('Product ID is required');
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (context) => RoomArPreparationViewModel(
              repository: context.read(),
              capabilityService: context.read(),
              productId: productId,
            ),
            child: RoomArPreparationView(productId: productId),
          ),
        );
      case RouteNames.roomArCoreSession:
        // Phase 9.2 R6 — the customer Tier-1 markerless-ARCore session for
        // ONE approved product. Same eligibility guarantee as roomArSession:
        // RoomArPreparationViewModel only builds a RoomArSessionArgs for a
        // product with `hasRenderableArModel == true`.
        final coreArgs = settings.arguments;
        if (coreArgs is! RoomArSessionArgs) {
          return _errorRoute('Room AR is not available for this product');
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (_) {
              final vm = RoomArCoreViewModel(args: coreArgs)..start();
              RoomArModelServiceFactory.open()
                  .then(vm.attachModelService)
                  .catchError((_) {});
              return vm;
            },
            child: const RoomArCoreView(),
          ),
        );
      case RouteNames.roomArSession:
        // Phase 9.2 R15/R17 — the customer Room-AR session for ONE approved
        // product. RoomArPreparationViewModel only builds a RoomArSessionArgs
        // when the product is one of the four approved products AND its live
        // arMetadata is renderable, so an ineligible product can never open
        // this screen.
        final sessionArgs = settings.arguments;
        if (sessionArgs is! RoomArSessionArgs) {
          return _errorRoute('Room AR is not available for this product');
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (_) {
              final vm = MarkerArViewModel(
                mode: MarkerArLaunchMode.customerProduct,
                // A placeholder when `sessionArgs.object` is null (any
                // product but the four originally-bundled ones) — never
                // reaches the native side as-is; see
                // `customerFirestoreProductId` and `MarkerArViewModel`'s
                // internal re-derivation of the real mapping.
                initialObject: sessionArgs.object ?? MarkerArObject.chair,
                customerMetadata: sessionArgs.metadata,
                customerFirestoreProductId: sessionArgs.firestoreProductId,
                customerProductTitle: sessionArgs.productTitle,
              )..start();
              // Production Storage GLB delivery (verified cache + integrity +
              // last-known-good + bundled fallback). If the cache dir can't be
              // opened, the engine simply runs on the bundled GLB.
              RoomArModelServiceFactory.open()
                  .then(vm.attachModelService)
                  .catchError((_) {});
              return vm;
            },
            child: const MarkerArView(),
          ),
        );
      case RouteNames.roomArPreview:
        // Phase 9.2 R7 — Tier-3 Interactive 3D Preview for ONE approved
        // product. Same eligibility guarantee as roomArSession: the prep
        // screen only produces a RoomArSessionArgs for an approved product
        // with renderable arMetadata, and the Tier-2 camera screen only
        // forwards its own (already-valid) args here.
        final previewArgs = settings.arguments;
        if (previewArgs is! RoomArSessionArgs) {
          return _errorRoute(
            'The 3D preview is not available for this product',
          );
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (_) {
              final vm = RoomArPreviewViewModel(args: previewArgs)..start();
              RoomArModelServiceFactory.open()
                  .then(vm.attachModelService)
                  .catchError((_) {});
              return vm;
            },
            child: const RoomArPreviewView(),
          ),
        );
      case RouteNames.roomArMarkerEngine:
        // Phase 9.2 R5 — internal Tier-2 Marker-AR engine verification screen.
        // Self-contained: its channel + calibration store are leaf infra, not
        // shared providers, so they are constructed here rather than in
        // AppProviders.
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (_) {
              final vm = MarkerArViewModel()..start();
              // Phase 9.2 R10 — debug-only: attach the Firebase Storage GLB
              // delivery service once its on-disk cache has resolved. Compiled
              // out of release builds; customer entry points stay disabled.
              if (kDebugMode) {
                RoomArModelServiceFactory.open()
                    .then(vm.attachModelService)
                    .catchError((_) {});
              }
              return vm;
            },
            child: const MarkerArView(),
          ),
        );
      case RouteNames.cart:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (context) => CartViewModel(
              context.read<CustomerShoppingState>(),
              context.read<ProductDetailsRepository>(),
            ),
            child: const ShoppingCartView(),
          ),
        );
      case RouteNames.virtualTryOnSetup:
        final productId = settings.arguments as String?;
        if (productId == null) return _errorRoute('Product ID is required');
        return MaterialPageRoute(
          builder: (_) => ChangeNotifierProvider(
            create: (context) => VirtualTryOnSetupViewModel(
              repository: context.read(),
              productId: productId,
            ),
            child: const VirtualTryOnSetupView(),
          ),
        );
      case RouteNames.deliveryAddress:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const DeliveryAddressView(),
        );
      case RouteNames.addressForm:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AddressFormView(),
        );
      case RouteNames.savedAddresses:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const SavedAddressesView(),
        );
      case RouteNames.favorites:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const FavoritesView(),
        );
      case RouteNames.recentlyViewed:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const RecentlyViewedView(),
        );
      case RouteNames.orders:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (context) => MyOrdersViewModel(
              orderState: context.read<CustomerOrderState>(),
            ),
            child: const MyOrdersView(),
          ),
        );
      case RouteNames.orderDetail:
        final orderId = settings.arguments as String?;
        if (orderId == null) return _errorRoute('Order ID is required');
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (context) => OrderDetailViewModel(
              orderState: context.read<CustomerOrderState>(),
              orderId: orderId,
            ),
            child: const OrderDetailView(),
          ),
        );
      case RouteNames.adminDashboard:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminDashboardView(),
        );
      case RouteNames.adminProducts:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminProductsView(),
        );
      case RouteNames.adminAddProduct:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminProductFormView(),
        );
      case RouteNames.adminEditProduct:
        final productId = settings.arguments as String?;
        if (productId == null) {
          return _errorRoute('Product ID is required for edit');
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AdminProductFormView(productId: productId),
        );
      case RouteNames.adminAddCategory:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminCategoryFormView(),
        );
      case RouteNames.adminEditCategory:
        final categoryId = settings.arguments as String?;
        if (categoryId == null) {
          return _errorRoute('Category ID is required for edit');
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => AdminCategoryFormView(categoryId: categoryId),
        );
      case RouteNames.adminArMedia:
        final arMediaArguments = settings.arguments;
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (context) => arMediaArguments is ArMediaRouteArguments
                ? ArMediaManagementViewModel.productScoped(
                    arMediaArguments.product,
                    storageService: context.read<StorageService>(),
                  )
                : ArMediaManagementViewModel.general(
                    context.read<CommerceDatabase>(),
                    storageService: context.read<StorageService>(),
                  ),
            child: const AdminArMediaManagementView(),
          ),
        );
      case RouteNames.adminArModelPreview:
        // Phase 9.2 R16 — admin-only. Reachable only from the AR & Media
        // screen (itself an admin surface); a malformed argument errors out.
        final previewArgs = settings.arguments;
        if (previewArgs is! AdminArModelPreviewArgs) {
          return _errorRoute('No model to preview');
        }
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (context) => AdminArModelPreviewViewModel(
              args: previewArgs,
              storage: context.read<StorageService>(),
            )..start(),
            child: const AdminArModelPreviewView(),
          ),
        );
      case RouteNames.adminInventory:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminInventoryView(),
        );
      case RouteNames.adminOrders:
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => const AdminOrdersView(),
        );
      case RouteNames.adminOrderDetail:
        final orderId = settings.arguments as String?;
        if (orderId == null) return _errorRoute('Order ID is required');
        return MaterialPageRoute(
          settings: settings,
          builder: (_) => ChangeNotifierProvider(
            create: (context) => AdminOrderDetailViewModel(
              context.read<CommerceDatabase>(),
              orderId: orderId,
            ),
            child: const AdminOrderDetailView(),
          ),
        );
      default:
        return _errorRoute(settings.name);
    }
  }

  static Route<dynamic> _errorRoute(String? name) {
    return MaterialPageRoute(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Error')),
        body: Center(
          child: Text(
            'No route defined for $name',
            style: AppTypography.bodyLarge.copyWith(color: AppColors.error),
          ),
        ),
      ),
    );
  }
}
