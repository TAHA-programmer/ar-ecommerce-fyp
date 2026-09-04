import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/views/profile_view.dart';
import 'package:twin_ar/core/widgets/navigation/customer_bottom_navigation.dart';

const _uid = 'test-uid';

void main() {
  Future<Widget> createTestWidget() async {
    final repository = MockUserProfileRepository(
      seed: {
        _uid: const UserProfileModel(
          uid: _uid,
          email: 'neha.sharma@gmail.com',
          displayName: 'Neha Sharma',
          phone: '+91 98765 43210',
          role: 'customer',
        ),
      },
    );
    final profileState = CustomerProfileState(repository);
    await profileState.loadForUser(_uid);

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CustomerProfileState>.value(value: profileState),
        ChangeNotifierProvider(
          create: (_) => CustomerShoppingState(
            MockFavoritesRepository(),
            MockCartRepository(),
          ),
        ),
      ],
      child: const MaterialApp(home: ProfileView()),
    );
  }

  testWidgets('ProfileView renders correctly without back button', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(await createTestWidget());

    // Header exists
    expect(find.text('Profile'), findsOneWidget);

    // No back button in header (we check specifically for the back icon)
    // The profile card has an Edit Profile button, so we ensure no back_ios icon exists
    expect(find.byIcon(Icons.arrow_back_ios), findsNothing);

    // Profile card displays the real signed-in user's loaded profile
    expect(find.text('Neha Sharma'), findsOneWidget);
    expect(find.text('neha.sharma@gmail.com'), findsOneWidget);
    expect(find.text('+91 98765 43210'), findsOneWidget);

    // Edit Profile button
    expect(find.text('Edit Profile'), findsOneWidget);

    // Menu items
    expect(find.text('My Orders'), findsOneWidget);
    expect(find.text('Help and Support'), findsOneWidget);
    expect(find.text('Log Out'), findsOneWidget);

    // Bottom Navigation
    expect(find.byType(CustomerBottomNavigation), findsOneWidget);
  });
}
