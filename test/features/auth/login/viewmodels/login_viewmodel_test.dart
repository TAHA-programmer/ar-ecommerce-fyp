import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/features/auth/login/viewmodels/login_viewmodel.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/features/auth/services/remembered_login_store.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';

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
}
