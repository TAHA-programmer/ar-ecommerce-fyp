import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/app.dart';
import 'package:twin_ar/core/data/mock_address_repository.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';

void main() {
  testWidgets('App root widget builds smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame. Uses TWinArApp's test-only
    // authRepositoryOverride/userProfileRepositoryOverride/
    // commerceDatabaseOverride/categoryRepositoryOverride/
    // addressRepositoryOverride/favoritesRepositoryOverride/
    // cartRepositoryOverride (see AppProviders.providers) so this smoke
    // test doesn't require a real Firebase backend - production always uses
    // the real Firestore-backed implementations.
    await tester.pumpWidget(
      TWinArApp(
        authRepositoryOverride: MockAuthRepository(),
        userProfileRepositoryOverride: MockUserProfileRepository(),
        commerceDatabaseOverride: MockCommerceDatabase(),
        categoryRepositoryOverride: MockCategoryRepository(),
        addressRepositoryOverride: MockAddressRepository(),
        favoritesRepositoryOverride: MockFavoritesRepository(),
        cartRepositoryOverride: MockCartRepository(),
      ),
    );

    // Pump to allow timers in SplashView to finish
    await tester.pumpAndSettle(const Duration(seconds: 3));

    // After splash screen, it should navigate to CustomerMainNavigation
    // But for this smoke test, just verifying it builds without crashing is fine
  });
}
