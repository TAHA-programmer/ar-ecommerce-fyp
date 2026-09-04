import '../../../core/models/auth/auth_result.dart';
import '../../../core/models/auth/user_role.dart';
import 'auth_repository.dart';

class MockAuthRepository implements AuthRepository {
  // DEVELOPMENT-ONLY credentials
  static const _customerEmail = 'customer@twinar.com';
  static const _customerPassword = 'Customer123';

  static const _adminEmail = 'admin@twinar.com';
  static const _adminPassword = 'Admin123';

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    // Mock network delay
    await Future.delayed(const Duration(milliseconds: 800));

    final normalizedEmail = email.trim().toLowerCase();

    if (normalizedEmail == _customerEmail.toLowerCase() &&
        password == _customerPassword) {
      return AuthResult.success(
        userId: 'mock_customer_id',
        email: _customerEmail,
        role: UserRole.customer,
      );
    }

    if (normalizedEmail == _adminEmail.toLowerCase() &&
        password == _adminPassword) {
      return AuthResult.success(
        userId: 'mock_admin_id',
        email: _adminEmail,
        role: UserRole.superAdmin,
      );
    }

    return AuthResult.failure(errorMessage: 'Invalid email or password.');
  }

  @override
  Future<void> signOut() async {
    // Mock network delay
    await Future.delayed(const Duration(milliseconds: 500));
  }

  @override
  Future<String?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String phone,
  }) async {
    // Mock network delay
    await Future.delayed(const Duration(milliseconds: 800));
    return null; // Always succeeds
  }

  @override
  Future<String?> sendPasswordResetEmail({required String email}) async {
    // Mock network delay
    await Future.delayed(const Duration(milliseconds: 800));
    return null; // Always succeeds
  }

  @override
  Stream<AuthResult?> authStateChanges() => Stream<AuthResult?>.value(null);
}
