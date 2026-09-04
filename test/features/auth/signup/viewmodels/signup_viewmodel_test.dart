import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';
import 'package:twin_ar/features/auth/signup/viewmodels/signup_viewmodel.dart';

void main() {
  late SignupViewModel viewModel;

  setUp(() {
    viewModel = SignupViewModel(MockAuthRepository());
  });

  group('SignupViewModel Tests', () {
    test('initial state is correct', () {
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.termsAccepted, isFalse);
    });

    test('toggleTermsAccepted changes state correctly', () {
      viewModel.toggleTermsAccepted(true);
      expect(viewModel.termsAccepted, isTrue);

      viewModel.toggleTermsAccepted(false);
      expect(viewModel.termsAccepted, isFalse);

      viewModel.toggleTermsAccepted(null);
      expect(viewModel.termsAccepted, isFalse);
    });

    test('validateAndSignUp rejects empty name', () async {
      final result = await viewModel.validateAndSignUp(
        name: ' ',
        email: 'test@example.com',
        phone: '03001234567',
        password: 'Password123!',
        confirmPassword: 'Password123!',
      );
      expect(result, SignupResult.invalidName);
    });

    test('validateAndSignUp rejects invalid email', () async {
      final result = await viewModel.validateAndSignUp(
        name: 'John Doe',
        email: 'invalid-email',
        phone: '03001234567',
        password: 'Password123!',
        confirmPassword: 'Password123!',
      );
      expect(result, SignupResult.invalidEmail);
    });

    // Phase 8.12: the phone must be a standard Pakistani local mobile
    // number (^03[0-9]{9}$) - the client validator matches the
    // `users/{uid}.phone` Firestore rule exactly, so the user gets a clean
    // message, never a permission-denied.
    group('validateAndSignUp phone (Pakistani local mobile 03XXXXXXXXX)', () {
      Future<SignupResult> withPhone(String phone) =>
          viewModel.validateAndSignUp(
            name: 'John Doe',
            email: 'test@example.com',
            phone: phone,
            password: 'Password123!',
            confirmPassword: 'Password123!',
          );

      test('accepts a valid 03XXXXXXXXX number', () async {
        viewModel.toggleTermsAccepted(true);
        expect(await withPhone('03001234567'), SignupResult.success);
      });

      test('rejects fewer than 11 digits', () async {
        expect(await withPhone('0300123456'), SignupResult.invalidPhone);
      });

      test('rejects more than 11 digits', () async {
        expect(await withPhone('030012345678'), SignupResult.invalidPhone);
      });

      test('rejects a wrong prefix (not 03)', () async {
        expect(await withPhone('04001234567'), SignupResult.invalidPhone);
        expect(await withPhone('13001234567'), SignupResult.invalidPhone);
      });

      test('rejects the +92 / international format', () async {
        expect(await withPhone('+923001234567'), SignupResult.invalidPhone);
        expect(await withPhone('923001234567'), SignupResult.invalidPhone);
      });

      test('rejects spaces and hyphens', () async {
        expect(await withPhone('0300 123 4567'), SignupResult.invalidPhone);
        expect(await withPhone('0300-123-4567'), SignupResult.invalidPhone);
      });

      test('rejects letters', () async {
        expect(await withPhone('0300abcdefg'), SignupResult.invalidPhone);
      });

      test('rejects an empty value', () async {
        expect(await withPhone(''), SignupResult.invalidPhone);
      });
    });

    // Phase 8.12: the approved display-name validation (1-100 chars) is
    // unchanged.
    test(
      'validateAndSignUp rejects a name longer than 100 characters',
      () async {
        final result = await viewModel.validateAndSignUp(
          name: 'a' * 101,
          email: 'test@example.com',
          phone: '03001234567',
          password: 'Password123!',
          confirmPassword: 'Password123!',
        );
        expect(result, SignupResult.invalidName);
      },
    );

    test(
      'validateAndSignUp accepts a 100-char name with a valid phone',
      () async {
        viewModel.toggleTermsAccepted(true);
        final result = await viewModel.validateAndSignUp(
          name: 'a' * 100,
          email: 'test@example.com',
          phone: '03001234567',
          password: 'Password123!',
          confirmPassword: 'Password123!',
        );
        expect(result, SignupResult.success);
      },
    );

    group('validateAndSignUp password strength', () {
      test('rejects password under 8 characters', () async {
        final result = await viewModel.validateAndSignUp(
          name: 'John Doe',
          email: 'test@example.com',
          phone: '03001234567',
          password: 'Ab1!xyz', // 7 chars
          confirmPassword: 'Ab1!xyz',
        );
        expect(result, SignupResult.passwordTooWeak);
      });

      test('rejects password missing an uppercase letter', () async {
        final result = await viewModel.validateAndSignUp(
          name: 'John Doe',
          email: 'test@example.com',
          phone: '03001234567',
          password: 'password123!',
          confirmPassword: 'password123!',
        );
        expect(result, SignupResult.passwordTooWeak);
      });

      test('rejects password missing a lowercase letter', () async {
        final result = await viewModel.validateAndSignUp(
          name: 'John Doe',
          email: 'test@example.com',
          phone: '03001234567',
          password: 'PASSWORD123!',
          confirmPassword: 'PASSWORD123!',
        );
        expect(result, SignupResult.passwordTooWeak);
      });

      test('rejects password missing a digit', () async {
        final result = await viewModel.validateAndSignUp(
          name: 'John Doe',
          email: 'test@example.com',
          phone: '03001234567',
          password: 'Password!!!',
          confirmPassword: 'Password!!!',
        );
        expect(result, SignupResult.passwordTooWeak);
      });

      test('rejects password missing a special character', () async {
        final result = await viewModel.validateAndSignUp(
          name: 'John Doe',
          email: 'test@example.com',
          phone: '03001234567',
          password: 'Password123',
          confirmPassword: 'Password123',
        );
        expect(result, SignupResult.passwordTooWeak);
      });

      test('accepts a password satisfying every rule', () async {
        viewModel.toggleTermsAccepted(true);
        final result = await viewModel.validateAndSignUp(
          name: 'John Doe',
          email: 'test@example.com',
          phone: '03001234567',
          password: 'Password123!',
          confirmPassword: 'Password123!',
        );
        expect(result, SignupResult.success);
      });
    });

    test('validateAndSignUp rejects mismatched confirm password', () async {
      final result = await viewModel.validateAndSignUp(
        name: 'John Doe',
        email: 'test@example.com',
        phone: '03001234567',
        password: 'Password123!',
        confirmPassword: 'Password456!',
      );
      expect(result, SignupResult.passwordMismatch);
    });

    test('validateAndSignUp rejects when terms not accepted', () async {
      viewModel.toggleTermsAccepted(false);

      final result = await viewModel.validateAndSignUp(
        name: 'John Doe',
        email: 'test@example.com',
        phone: '03001234567',
        password: 'Password123!',
        confirmPassword: 'Password123!',
      );
      expect(result, SignupResult.termsNotAccepted);
    });

    test(
      'validateAndSignUp succeeds with valid input and terms accepted',
      () async {
        viewModel.toggleTermsAccepted(true);

        // We don't await here yet so we can check isLoading
        final futureResult = viewModel.validateAndSignUp(
          name: 'John Doe',
          email: 'test@example.com',
          phone: '03001234567',
          password: 'Password123!',
          confirmPassword: 'Password123!',
        );

        expect(viewModel.isLoading, isTrue);

        final result = await futureResult;

        expect(result, SignupResult.success);
        expect(viewModel.isLoading, isFalse);
      },
    );
  });
}
