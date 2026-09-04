import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/features/auth/forgot_password/viewmodels/forgot_password_viewmodel.dart';

void main() {
  group('ForgotPasswordViewModel Tests', () {
    late ForgotPasswordViewModel viewModel;

    setUp(() {
      viewModel = ForgotPasswordViewModel(MockAuthRepository());
    });

    test('initial state is correct', () {
      expect(viewModel.isLoading, false);
    });

    test('sendResetLink rejects empty email', () async {
      final result = await viewModel.sendResetLink(email: '   ');
      expect(result, ForgotPasswordResult.emptyEmail);
      expect(viewModel.isLoading, false);
    });

    test('sendResetLink rejects invalid email', () async {
      final result = await viewModel.sendResetLink(email: 'invalid-email');
      expect(result, ForgotPasswordResult.invalidEmail);
      expect(viewModel.isLoading, false);
    });

    test('sendResetLink succeeds with valid email', () async {
      // We don't await immediately so we can check loading state
      final futureResult = viewModel.sendResetLink(email: 'test@example.com');

      // Loading state should be true synchronously after calling
      expect(viewModel.isLoading, true);

      final result = await futureResult;

      expect(result, ForgotPasswordResult.success);
      expect(viewModel.isLoading, false);
    });
  });
}
