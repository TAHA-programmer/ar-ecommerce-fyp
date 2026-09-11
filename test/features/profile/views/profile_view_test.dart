import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/views/profile_view.dart';
import 'package:twin_ar/core/widgets/navigation/customer_bottom_navigation.dart';
import 'package:twin_ar/features/virtual_try_on/services/mock_virtual_try_on_service.dart';
import 'package:twin_ar/features/virtual_try_on/services/virtual_try_on_service.dart';

const _uid = 'test-uid';

void main() {
  Future<Widget> createTestWidget({MockVirtualTryOnService? vtoService}) async {
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

    final authState = AuthSessionState();
    authState.setSession(
      AuthResult.success(
        userId: _uid,
        email: 'neha.sharma@gmail.com',
        role: UserRole.customer,
      ),
    );

    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CustomerProfileState>.value(value: profileState),
        ChangeNotifierProvider(
          create: (_) => CustomerShoppingState(
            MockFavoritesRepository(),
            MockCartRepository(),
          ),
        ),
        ChangeNotifierProvider<AuthSessionState>.value(value: authState),
        Provider<VirtualTryOnService>.value(
          value: vtoService ?? MockVirtualTryOnService(),
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

  group('Delete My Try-On Data (Phase 9.3 Stage 5 hardening)', () {
    Future<void> tapDeleteMenuItemAndConfirm(WidgetTester tester) async {
      final menuItem = find.text('Delete My Try-On Data');
      await tester.ensureVisible(menuItem);
      await tester.pumpAndSettle();
      await tester.tap(menuItem);
      await tester.pumpAndSettle();

      expect(find.text('Delete My Try-On Data?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pump(); // let the async delete + toast fire
      await tester.pump();
    }

    /// `AppToast` schedules a real 3s auto-dismiss `Timer` and holds STATIC
    /// state shared across every test in this file — an un-drained timer
    /// from one test fires mid-teardown or during a LATER test's widget
    /// tree, crashing with "AnimationController used after dispose". Call
    /// this after asserting on a toast's text, before the test ends, so the
    /// toast fully dismisses itself while its own tree is still mounted.
    Future<void> drainToast(WidgetTester tester) async {
      await tester.pump(const Duration(seconds: 4));
    }

    testWidgets('shows a truthful success toast when everything is deleted', (
      tester,
    ) async {
      final service = MockVirtualTryOnService()
        ..deleteAllTryOnDataResult = const VirtualTryOnDataDeletionResult(
          outcome: VirtualTryOnDataDeletionOutcome.success,
          sessionsFound: 2,
        );
      await tester.pumpWidget(await createTestWidget(vtoService: service));

      await tapDeleteMenuItemAndConfirm(tester);

      expect(service.deleteAllTryOnDataCalls, 1);
      expect(find.textContaining('have been deleted'), findsOneWidget);
      await drainToast(tester);
    });

    testWidgets(
      'shows an honest "nothing found" success toast when there is no data',
      (tester) async {
        final service = MockVirtualTryOnService()
          ..deleteAllTryOnDataResult = const VirtualTryOnDataDeletionResult(
            outcome: VirtualTryOnDataDeletionOutcome.success,
            sessionsFound: 0,
          );
        await tester.pumpWidget(await createTestWidget(vtoService: service));

        await tapDeleteMenuItemAndConfirm(tester);

        expect(find.textContaining('No saved Virtual Try-On'), findsOneWidget);
        await drainToast(tester);
      },
    );

    testWidgets(
      'NEVER shows success when the deletion only partially succeeded',
      (tester) async {
        final service = MockVirtualTryOnService()
          ..deleteAllTryOnDataResult = const VirtualTryOnDataDeletionResult(
            outcome: VirtualTryOnDataDeletionOutcome.partial,
            sessionsFound: 3,
          );
        await tester.pumpWidget(await createTestWidget(vtoService: service));

        await tapDeleteMenuItemAndConfirm(tester);

        expect(find.textContaining('could not be deleted'), findsOneWidget);
        expect(find.textContaining('have been deleted'), findsNothing);
        await drainToast(tester);
      },
    );

    testWidgets(
      'NEVER shows success when the underlying query/cleanup failed entirely',
      (tester) async {
        final service = MockVirtualTryOnService()
          ..deleteAllTryOnDataResult = const VirtualTryOnDataDeletionResult(
            outcome: VirtualTryOnDataDeletionOutcome.failed,
            sessionsFound: 0,
          );
        await tester.pumpWidget(await createTestWidget(vtoService: service));

        await tapDeleteMenuItemAndConfirm(tester);

        expect(
          find.textContaining("couldn't delete your Virtual Try-On data"),
          findsOneWidget,
        );
        expect(find.textContaining('have been deleted'), findsNothing);
        expect(find.textContaining('No saved Virtual Try-On'), findsNothing);
        await drainToast(tester);
      },
    );

    testWidgets('cancelling the confirmation dialog calls nothing', (
      tester,
    ) async {
      final service = MockVirtualTryOnService();
      await tester.pumpWidget(await createTestWidget(vtoService: service));

      final menuItem = find.text('Delete My Try-On Data');
      await tester.ensureVisible(menuItem);
      await tester.pumpAndSettle();
      await tester.tap(menuItem);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(service.deleteAllTryOnDataCalls, 0);
    });
  });
}
