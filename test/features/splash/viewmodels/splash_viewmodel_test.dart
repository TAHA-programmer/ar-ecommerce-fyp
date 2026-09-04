import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/splash/viewmodels/splash_viewmodel.dart';

void main() {
  group('SplashViewModel', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('starts in loading state', () {
      final authState = AuthSessionState(); // no repository: ready immediately
      final viewModel = SplashViewModel(authState);
      expect(viewModel.state, SplashState.loading);
    });

    test(
      'becomes complete and reports isAuthenticated=false for a signed-out session',
      () async {
        final authState = AuthSessionState();
        final viewModel = SplashViewModel(authState);

        var notified = false;
        viewModel.addListener(() => notified = true);
        viewModel.initialize();

        // Real branding timer is 2500ms; wait past it.
        await Future<void>.delayed(const Duration(milliseconds: 2600));

        expect(notified, isTrue);
        expect(viewModel.state, SplashState.complete);
        expect(viewModel.isAuthenticated, isFalse);
        expect(viewModel.isSuperAdmin, isFalse);
      },
    );

    test(
      'reports isAuthenticated=true and the correct role for a pre-existing session',
      () async {
        final authState = AuthSessionState();
        authState.setSession(
          AuthResult.success(
            userId: 'u1',
            email: 'shopper@example.com',
            role: UserRole.customer,
          ),
        );
        final viewModel = SplashViewModel(authState);
        viewModel.initialize();

        await Future<void>.delayed(const Duration(milliseconds: 2600));

        expect(viewModel.state, SplashState.complete);
        expect(viewModel.isAuthenticated, isTrue);
        expect(viewModel.isSuperAdmin, isFalse);
      },
    );

    test('reports isSuperAdmin=true for an admin session', () async {
      final authState = AuthSessionState();
      authState.setSession(
        AuthResult.success(
          userId: 'u2',
          email: 'admin@twinar.com',
          role: UserRole.superAdmin,
        ),
      );
      final viewModel = SplashViewModel(authState);
      viewModel.initialize();

      await Future<void>.delayed(const Duration(milliseconds: 2600));

      expect(viewModel.state, SplashState.complete);
      expect(viewModel.isAuthenticated, isTrue);
      expect(viewModel.isSuperAdmin, isTrue);
    });
  });

  group('SplashViewModel - onboarding persistence', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('defaults hasCompletedOnboarding=false on a fresh install', () async {
      final authState = AuthSessionState();
      final viewModel = SplashViewModel(authState);
      viewModel.initialize();

      await Future<void>.delayed(const Duration(milliseconds: 2600));

      expect(viewModel.hasCompletedOnboarding, isFalse);
    });

    test(
      'reports hasCompletedOnboarding=true when the local flag was already set',
      () async {
        SharedPreferences.setMockInitialValues({
          'has_completed_onboarding': true,
        });
        final authState = AuthSessionState();
        final viewModel = SplashViewModel(authState);
        viewModel.initialize();

        await Future<void>.delayed(const Duration(milliseconds: 2600));

        expect(viewModel.hasCompletedOnboarding, isTrue);
        expect(viewModel.isAuthenticated, isFalse);
      },
    );
  });
}
