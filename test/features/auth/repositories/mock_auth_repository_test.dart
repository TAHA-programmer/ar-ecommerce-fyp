import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/auth/repositories/mock_auth_repository.dart';

void main() {
  late MockAuthRepository repository;

  setUp(() {
    repository = MockAuthRepository();
  });

  group('MockAuthRepository', () {
    test('successful customer login', () async {
      final result = await repository.signIn(
        email: 'customer@twinar.com',
        password: 'Customer123',
      );

      expect(result.success, isTrue);
      expect(result.role, equals(UserRole.customer));
      expect(result.email, equals('customer@twinar.com'));
      expect(result.userId, equals('mock_customer_id'));
    });

    test('successful superAdmin login', () async {
      final result = await repository.signIn(
        email: 'admin@twinar.com',
        password: 'Admin123',
      );

      expect(result.success, isTrue);
      expect(result.role, equals(UserRole.superAdmin));
      expect(result.email, equals('admin@twinar.com'));
      expect(result.userId, equals('mock_admin_id'));
    });

    test(
      'successful superAdmin login with whitespace and uppercase email',
      () async {
        final result = await repository.signIn(
          email: ' ADMIN@TWINAR.COM ',
          password: 'Admin123',
        );

        expect(result.success, isTrue);
        expect(result.role, equals(UserRole.superAdmin));
      },
    );

    test('failed login with correct email but wrong-case password', () async {
      final result = await repository.signIn(
        email: 'admin@twinar.com',
        password: 'admin123',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals('Invalid email or password.'));
      expect(result.role, isNull);
    });

    test('failed login with incorrect password', () async {
      final result = await repository.signIn(
        email: 'customer@twinar.com',
        password: 'wrongpassword',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, equals('Invalid email or password.'));
    });
  });

  group('MockAuthRepository - signUp', () {
    test('always succeeds (null error)', () async {
      final error = await repository.signUp(
        email: 'new@example.com',
        password: 'Password123!',
        displayName: 'New User',
        phone: '1234567890',
      );
      expect(error, isNull);
    });
  });

  group('MockAuthRepository - sendPasswordResetEmail', () {
    test('always succeeds (null error)', () async {
      final error = await repository.sendPasswordResetEmail(
        email: 'customer@twinar.com',
      );
      expect(error, isNull);
    });
  });

  group('MockAuthRepository - signOut', () {
    test('completes without throwing', () async {
      await expectLater(repository.signOut(), completes);
    });
  });

  group('MockAuthRepository - authStateChanges', () {
    test('emits a single null (no persisted mock session)', () async {
      final results = await repository.authStateChanges().toList();
      expect(results, [null]);
    });
  });
}
