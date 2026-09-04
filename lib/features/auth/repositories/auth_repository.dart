import '../../../core/models/auth/auth_result.dart';

abstract class AuthRepository {
  Future<AuthResult> signIn({required String email, required String password});

  /// Creates a new account and its `users/{uid}` Firestore profile
  /// (`role: 'customer'` always). Returns `null` on success, or a
  /// user-friendly error message on failure. Does not establish a session.
  Future<String?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String phone,
  });

  Future<void> signOut();

  /// Sends a password-reset email. Returns `null` on success, or a
  /// user-friendly error message on failure.
  Future<String?> sendPasswordResetEmail({required String email});

  /// Emits the current session as an [AuthResult] whenever the underlying
  /// auth state changes (including the initial state on subscription), or
  /// `null` when signed out.
  Stream<AuthResult?> authStateChanges();
}
