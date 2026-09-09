class RouteNames {
  RouteNames._();

  static const String splash = '/';
  static const String onboarding = '/onboarding';

  // Auth
  static const String login = '/login';
  static const String signUp = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String myMeasurements = '/my_measurements';
  static const String terms = '/terms';
  static const String privacy = '/privacy';

  // Customer
  static const String home = '/home';
  static const String explore = '/explore';
  static const String productDetails = '/product-details';
  static const String virtualTryOnSetup = '/virtual-try-on-setup';
  static const String roomArPreparation = '/room-ar-preparation';

  /// Phase 9.2 R5 — internal Tier-2 Marker-AR engine verification surface
  /// (debug-only entry from Profile). Not a customer "View in Room" route.
  static const String roomArMarkerEngine = '/room-ar/marker-engine';

  /// Phase 9.2 R15/R17 — the customer Tier-2 Marker-AR session for ONE
  /// approved product, reached from the Room-AR preparation screen's
  /// "Start AR" button. Expects a `RoomArSessionArgs`.
  static const String roomArSession = '/room-ar/session';

  /// Phase 9.2 R6 — the customer Tier-1 markerless-ARCore session for ONE
  /// approved product, reached when capability routing (R8) picks Tier 1.
  /// Expects a `RoomArSessionArgs`.
  static const String roomArCoreSession = '/room-ar/arcore-session';

  /// Phase 9.2 R7 — Tier-3 Interactive 3D Preview for ONE approved product,
  /// reached when capability routing (R8) picks Tier 3, or as the honest
  /// fallback from the Tier-2 camera screen. Expects a `RoomArSessionArgs`.
  static const String roomArPreview = '/room-ar/preview';
  static const String cart = '/cart';
  static const String deliveryAddress = '/delivery-address';
  static const String addressForm = '/address-form';
  static const String orderResult = '/order-result';
  static const String checkout = '/checkout';
  static const String profile = '/profile';
  static const String favorites = '/favorites';
  static const String recentlyViewed = '/recently-viewed';
  static const String savedAddresses = '/saved-addresses';
  static const String editProfile = '/edit-profile';
  static const String helpSupport = '/help-support';
  static const String roomArInfo = '/room-ar-info';
  static const String virtualTryOnInfo = '/virtual-try-on-info';
  static const String aboutTwinAr = '/about-twin-ar';
  static const String orders = '/orders';
  static const String orderDetail = '/order-detail';

  // Admin Routes
  static const String adminDashboard = '/admin/dashboard';
  static const String adminProducts = '/admin/products';
  static const String adminAddProduct = '/admin/products/add';
  static const String adminEditProduct = '/admin/products/edit';
  static const String adminAddCategory = '/admin/categories/add';
  static const String adminEditCategory = '/admin/categories/edit';
  static const String adminArMedia = '/admin/ar-media';
  // Phase 9.2 R16 — admin-only 3D preview of a staged/committed Room-AR model.
  static const String adminArModelPreview = '/admin/ar-media/preview';
  static const String adminInventory = '/admin/inventory';
  static const String adminOrders = '/admin/orders';
  static const String adminOrderDetail = '/admin/orders/detail';
}
