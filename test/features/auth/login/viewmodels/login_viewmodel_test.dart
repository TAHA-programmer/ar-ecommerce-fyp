import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/auth/login/viewmodels/login_viewmodel.dart';
import 'package:twin_ar/features/auth/repositories/auth_repository.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/features/auth/services/remembered_login_store.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';

/// Wraps [MockAuthRepository] but makes [signInWithGoogle] fully
/// controllable, so cancellation/failure/duplicate-tap behavior can be
/// exercised independently of email/password login.
class _ConfigurableGoogleAuthRepository implements AuthRepository {
  final _delegate = MockAuthRepository();
  AuthResult Function()? nextGoogleResult;
  int googleCallCount = 0;

  @override
  Future<AuthResult> signInWithGoogle() async {
    googleCallCount++;
    // Yield once so a caller can reliably observe `isLoading == true`
    // before this resolves, mirroring a real network round-trip.
    await Future<void>.delayed(Duration.zero);
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
  group('LoginViewModel', () {
    late LoginViewModel viewModel;
    late AuthSessionState sessionState;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      sessionState = AuthSessionState();
      viewModel = LoginViewModel(MockAuthRepository(), sessionState);
    });

    test('initial state is empty and valid', () {
      expect(viewModel.email, '');
      expect(viewModel.password, '');
      expect(viewModel.isRememberMeChecked, false);
      expect(viewModel.isLoading, false);
    });

    test('updateEmail changes email', () {
      viewModel.updateEmail('test@test.com');
      expect(viewModel.email, 'test@test.com');
    });

    test('updatePassword changes password', () {
      viewModel.updatePassword('password123');
      expect(viewModel.password, 'password123');
    });

    test('toggleRememberMe changes state', () {
      viewModel.toggleRememberMe();
      expect(viewModel.isRememberMeChecked, true);
    });

    test('submitLogin fails with empty email', () async {
      final result = await viewModel.submitLogin();
      expect(result.success, isFalse);
    });

    test('submitLogin fails with invalid email', () async {
      viewModel.updateEmail('invalid_email');
      viewModel.updatePassword('password');
      final result = await viewModel.submitLogin();
      expect(result.success, isFalse);
    });

    test('submitLogin fails with empty password', () async {
      viewModel.updateEmail('customer@twinar.com');
      final result = await viewModel.submitLogin();
      expect(result.success, isFalse);
    });

    test(
      'submitLogin fails with incorrect password leaves session empty',
      () async {
        viewModel.updateEmail('customer@twinar.com');
        viewModel.updatePassword('wrongpassword');

        final result = await viewModel.submitLogin();

        expect(result.success, isFalse);
        expect(sessionState.isAuthenticated, isFalse);
      },
    );

    test(
      'submitLogin succeeds with valid customer credentials and stores session',
      () async {
        viewModel.updateEmail('customer@twinar.com');
        viewModel.updatePassword('Customer123');

        final futureResult = viewModel.submitLogin();
        expect(viewModel.isLoading, true);

        final result = await futureResult;
        expect(result.success, isTrue);
        expect(viewModel.isLoading, false);

        expect(sessionState.isAuthenticated, isTrue);
        expect(sessionState.isCustomer, isTrue);
        expect(sessionState.email, equals('customer@twinar.com'));
      },
    );

    test(
      'submitLogin succeeds with valid admin credentials and stores session',
      () async {
        viewModel.updateEmail('admin@twinar.com');
        viewModel.updatePassword('Admin123');

        final result = await viewModel.submitLogin();
        expect(result.success, isTrue);

        expect(sessionState.isAuthenticated, isTrue);
        expect(sessionState.isSuperAdmin, isTrue);
        expect(sessionState.email, equals('admin@twinar.com'));
      },
    );
  });

  group('LoginViewModel - Remember Me', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('checked at login saves the email for next time', () async {
      final sessionState = AuthSessionState();
      final viewModel = LoginViewModel(MockAuthRepository(), sessionState);
      viewModel.updateEmail('customer@twinar.com');
      viewModel.updatePassword('Customer123');
      viewModel.toggleRememberMe();

      await viewModel.submitLogin();

      final saved = await RememberedLoginStore().getSavedEmail();
      expect(saved, 'customer@twinar.com');
    });

    test('unchecked at login clears any previously saved email', () async {
      SharedPreferences.setMockInitialValues({
        'remembered_login_email': 'old@example.com',
      });
      final sessionState = AuthSessionState();
      final viewModel = LoginViewModel(MockAuthRepository(), sessionState);
      viewModel.updateEmail('customer@twinar.com');
      viewModel.updatePassword('Customer123');
      // Remember Me left unchecked.

      await viewModel.submitLogin();

      final saved = await RememberedLoginStore().getSavedEmail();
      expect(saved, isNull);
    });

    test(
      'a saved email pre-fills the field and checks Remember Me on next screen',
      () async {
        SharedPreferences.setMockInitialValues({
          'remembered_login_email': 'returning@example.com',
        });
        final sessionState = AuthSessionState();
        final viewModel = LoginViewModel(MockAuthRepository(), sessionState);

        // The load is asynchronous; wait for the notifyListeners it triggers.
        final completer = Completer<void>();
        viewModel.addListener(() {
          if (!completer.isCompleted) completer.complete();
        });
        await completer.future;

        expect(viewModel.email, 'returning@example.com');
        expect(viewModel.isRememberMeChecked, isTrue);
        // Password is never persisted or pre-filled.
        expect(viewModel.password, '');
      },
    );

    test('failed login does not save the email even if checked', () async {
      final sessionState = AuthSessionState();
      final viewModel = LoginViewModel(MockAuthRepository(), sessionState);
      viewModel.updateEmail('customer@twinar.com');
      viewModel.updatePassword('wrong-password');
      viewModel.toggleRememberMe();

      await viewModel.submitLogin();

      final saved = await RememberedLoginStore().getSavedEmail();
      expect(saved, isNull);
    });
  });

  group('LoginViewModel - submitGoogleSignIn', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    test('success stores the session', () async {
      final repository = _ConfigurableGoogleAuthRepository()
        ..nextGoogleResult = () => AuthResult.success(
          userId: 'google-uid',
          email: 'shopper@gmail.com',
          role: UserRole.customer,
        );
      final sessionState = AuthSessionState();
      final viewModel = LoginViewModel(repository, sessionState);

      final result = await viewModel.submitGoogleSignIn();

      expect(result.success, isTrue);
      expect(sessionState.isAuthenticated, isTrue);
      expect(sessionState.isCustomer, isTrue);
      expect(sessionState.email, 'shopper@gmail.com');
      expect(viewModel.isLoading, isFalse);
    });

    test(
      'isLoading is true while in flight and false again once resolved',
      () async {
        final repository = _ConfigurableGoogleAuthRepository()
          ..nextGoogleResult = () => AuthResult.success(
            userId: 'google-uid',
            email: 'shopper@gmail.com',
            role: UserRole.customer,
          );
        final viewModel = LoginViewModel(repository, AuthSessionState());

        final future = viewModel.submitGoogleSignIn();
        expect(viewModel.isLoading, isTrue);

        await future;
        expect(viewModel.isLoading, isFalse);
      },
    );

    test(
      'a cancelled Google flow leaves the session untouched and is reported as cancelled, not a failure',
      () async {
        final repository = _ConfigurableGoogleAuthRepository();
        // nextGoogleResult left unset -> AuthResult.cancelled().
        final sessionState = AuthSessionState();
        final viewModel = LoginViewModel(repository, sessionState);

        final result = await viewModel.submitGoogleSignIn();

        expect(result.success, isFalse);
        expect(result.cancelled, isTrue);
        expect(result.errorMessage, isNull);
        expect(sessionState.isAuthenticated, isFalse);
      },
    );

    test(
      'a genuine failure carries its message and leaves no session',
      () async {
        final repository = _ConfigurableGoogleAuthRepository()
          ..nextGoogleResult = () => AuthResult.failure(
            errorMessage: 'Google Sign-In is not set up correctly yet.',
          );
        final sessionState = AuthSessionState();
        final viewModel = LoginViewModel(repository, sessionState);

        final result = await viewModel.submitGoogleSignIn();

        expect(result.success, isFalse);
        expect(result.cancelled, isFalse);
        expect(
          result.errorMessage,
          'Google Sign-In is not set up correctly yet.',
        );
        expect(sessionState.isAuthenticated, isFalse);
      },
    );

    test(
      'a duplicate call while one is already in flight is ignored (never two concurrent attempts)',
      () async {
        final repository = _ConfigurableGoogleAuthRepository()
          ..nextGoogleResult = () => AuthResult.success(
            userId: 'google-uid',
            email: 'shopper@gmail.com',
            role: UserRole.customer,
          );
        final viewModel = LoginViewModel(repository, AuthSessionState());

        final first = viewModel.submitGoogleSignIn();
        final second = viewModel.submitGoogleSignIn();

        final secondResult = await second;
        expect(secondResult.cancelled, isTrue);
        expect(
          repository.googleCallCount,
          1,
          reason: 'the second, overlapping tap must never reach the repository',
        );

        await first;
      },
    );

    test(
      'a superAdmin custom claim resolves the same way as email/password login',
      () async {
        final repository = _ConfigurableGoogleAuthRepository()
          ..nextGoogleResult = () => AuthResult.success(
            userId: 'google-admin-uid',
            email: 'admin@gmail.com',
            role: UserRole.superAdmin,
          );
        final sessionState = AuthSessionState();
        final viewModel = LoginViewModel(repository, sessionState);

        await viewModel.submitGoogleSignIn();

        expect(sessionState.isSuperAdmin, isTrue);
      },
    );
  });
}
