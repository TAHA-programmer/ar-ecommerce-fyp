import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/auth/login/views/login_view.dart';
import 'package:twin_ar/features/auth/login/viewmodels/login_viewmodel.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/features/auth/widgets/social_login_button.dart';
import 'package:twin_ar/features/auth/widgets/auth_footer_link.dart';
import 'package:twin_ar/core/widgets/fields/app_text_field.dart';
import 'package:twin_ar/core/widgets/fields/app_password_field.dart';
import 'package:twin_ar/core/widgets/buttons/app_primary_button.dart';
import 'package:twin_ar/app/routes/route_names.dart';

/// Wraps [MockAuthRepository] but makes [signInWithGoogle] fully
/// controllable, so the button's cancel/failure/success handling can be
/// exercised without touching any real Google/Firebase code.
class _ConfigurableGoogleAuthRepository implements AuthRepository {
  final _delegate = MockAuthRepository();
  AuthResult Function()? nextGoogleResult;

  /// When set, [signInWithGoogle] awaits this instead of resolving via
  /// [nextGoogleResult] - lets a test hold the call "in flight" until it
  /// deliberately completes this, to observe loading/disabled UI state.
  Completer<AuthResult>? pendingGoogleResult;

  @override
  Future<AuthResult> signInWithGoogle() async {
    final pending = pendingGoogleResult;
    if (pending != null) return pending.future;
    return nextGoogleResult?.call() ?? AuthResult.cancelled();
  }

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) => _delegate.signIn(email: email, password: password);

  @override
  Future<String?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String phone,
  }) => _delegate.signUp(
    email: email,
    password: password,
    displayName: displayName,
    phone: phone,
  );

  @override
  Future<void> signOut() => _delegate.signOut();

  @override
  Future<String?> sendPasswordResetEmail({required String email}) =>
      _delegate.sendPasswordResetEmail(email: email);

  @override
  Stream<AuthResult?> authStateChanges() => _delegate.authStateChanges();
}

void main() {
  Widget createTestWidget({
    String? navigatedRoute,
    Function(String)? onNavigate,
    AuthRepository? authRepository,
  }) {
    SharedPreferences.setMockInitialValues({});
    return MaterialApp(
      routes: {
        RouteNames.home: (context) {
          if (onNavigate != null) onNavigate(RouteNames.home);
          return const Scaffold(body: Text('HomeView'));
        },
        RouteNames.adminDashboard: (context) {
          if (onNavigate != null) onNavigate(RouteNames.adminDashboard);
          return const Scaffold(body: Text('AdminDashboard'));
        },
      },
      builder: (context, child) {
        return MediaQuery(
          data: const MediaQueryData(size: Size(360, 640)),
          child: child!,
        );
      },
      home: MultiProvider(
        providers: [
          Provider<AuthRepository>(
            create: (_) => authRepository ?? MockAuthRepository(),
          ),
          ChangeNotifierProvider(create: (_) => AuthSessionState()),
          ChangeNotifierProvider(
            create: (context) => LoginViewModel(
              context.read<AuthRepository>(),
              context.read<AuthSessionState>(),
            ),
          ),
        ],
        child: const LoginView(),
      ),
    );
  }

  testWidgets(
    'LoginView renders without overflow on small screen and has required elements',
    (WidgetTester tester) async {
      await tester.pumpWidget(createTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(AppTextField), findsNWidgets(2));
      expect(find.byType(AppPasswordField), findsOneWidget);
      expect(find.text('Remember Me'), findsOneWidget);
      expect(find.text('Forgot Password?'), findsOneWidget);
      expect(find.byType(AppPrimaryButton), findsOneWidget);
      expect(find.byType(SocialLoginButton), findsOneWidget);
      expect(find.byType(AuthFooterLink), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Valid customer credentials navigate to Home', (
    WidgetTester tester,
  ) async {
    String? pushedRoute;
    await tester.pumpWidget(
      createTestWidget(onNavigate: (route) => pushedRoute = route),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.emailAddress,
      ),
      'customer@twinar.com',
    );
    await tester.enterText(find.byType(TextField).last, 'Customer123');

    final buttonFinder = find.byType(AppPrimaryButton);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle(
      const Duration(seconds: 1),
    ); // wait for mock network delay

    expect(pushedRoute, equals(RouteNames.home));
  });

  testWidgets('Valid admin credentials navigate to Admin Dashboard', (
    WidgetTester tester,
  ) async {
    String? pushedRoute;
    await tester.pumpWidget(
      createTestWidget(onNavigate: (route) => pushedRoute = route),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byWidgetPredicate(
        (w) => w is TextField && w.keyboardType == TextInputType.emailAddress,
      ),
      'admin@twinar.com',
    );
    await tester.enterText(find.byType(TextField).last, 'Admin123');

    final buttonFinder = find.byType(AppPrimaryButton);
    await tester.ensureVisible(buttonFinder);
    await tester.tap(buttonFinder);
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(pushedRoute, equals(RouteNames.adminDashboard));
  });

  group('Google Sign-In button', () {
    testWidgets('a successful customer sign-in navigates to Home', (
      WidgetTester tester,
    ) async {
      String? pushedRoute;
      final repository = _ConfigurableGoogleAuthRepository()
        ..nextGoogleResult = () => AuthResult.success(
          userId: 'google-uid',
          email: 'shopper@gmail.com',
          role: UserRole.customer,
        );
      await tester.pumpWidget(
        createTestWidget(
          authRepository: repository,
          onNavigate: (route) => pushedRoute = route,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(SocialLoginButton));
      await tester.tap(find.byType(SocialLoginButton));
      await tester.pumpAndSettle();

      expect(pushedRoute, equals(RouteNames.home));
    });

    testWidgets('a successful admin sign-in navigates to Admin Dashboard', (
      WidgetTester tester,
    ) async {
      String? pushedRoute;
      final repository = _ConfigurableGoogleAuthRepository()
        ..nextGoogleResult = () => AuthResult.success(
          userId: 'google-admin-uid',
          email: 'admin@gmail.com',
          role: UserRole.superAdmin,
        );
      await tester.pumpWidget(
        createTestWidget(
          authRepository: repository,
          onNavigate: (route) => pushedRoute = route,
        ),
      );
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(SocialLoginButton));
      await tester.tap(find.byType(SocialLoginButton));
      await tester.pumpAndSettle();

      expect(pushedRoute, equals(RouteNames.adminDashboard));
    });

    testWidgets(
      'the user cancelling the account picker shows no error toast and stays on Login',
      (WidgetTester tester) async {
        String? pushedRoute;
        // nextGoogleResult left unset -> AuthResult.cancelled().
        final repository = _ConfigurableGoogleAuthRepository();
        await tester.pumpWidget(
          createTestWidget(
            authRepository: repository,
            onNavigate: (route) => pushedRoute = route,
          ),
        );
        await tester.pumpAndSettle();

        await tester.ensureVisible(find.byType(SocialLoginButton));
        await tester.tap(find.byType(SocialLoginButton));
        await tester.pumpAndSettle();

        expect(pushedRoute, isNull);
        expect(find.byType(LoginView), findsOneWidget);
        // No SnackBar/toast of any kind.
        expect(find.byType(SnackBar), findsNothing);
      },
    );

    testWidgets('a genuine failure shows its message as an error toast', (
      WidgetTester tester,
    ) async {
      final repository = _ConfigurableGoogleAuthRepository()
        ..nextGoogleResult = () => AuthResult.failure(
          errorMessage: 'Google Sign-In is not set up correctly yet.',
        );
      await tester.pumpWidget(createTestWidget(authRepository: repository));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(SocialLoginButton));
      await tester.tap(find.byType(SocialLoginButton));
      await tester.pumpAndSettle();

      expect(
        find.text('Google Sign-In is not set up correctly yet.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4)); // drain AppToast timer
    });

    testWidgets('the button is disabled while a Google sign-in is in flight', (
      WidgetTester tester,
    ) async {
      final completer = Completer<AuthResult>();
      final repository = _ConfigurableGoogleAuthRepository()
        ..pendingGoogleResult = completer;
      await tester.pumpWidget(createTestWidget(authRepository: repository));
      await tester.pumpAndSettle();

      await tester.ensureVisible(find.byType(SocialLoginButton));
      await tester.tap(find.byType(SocialLoginButton));
      // Held "in flight" by `completer` until we explicitly complete it
      // below - one pump is enough to observe the disabled state.
      await tester.pump();

      final wrapper = tester.widget<Opacity>(
        find.byKey(const Key('google_signin_loading_wrapper')),
      );
      expect(wrapper.opacity, lessThan(1.0));

      completer.complete(
        AuthResult.success(
          userId: 'google-uid',
          email: 'shopper@gmail.com',
          role: UserRole.customer,
        ),
      );
      await tester.pumpAndSettle();
    });
  });
}
