import 'user_role.dart';

class AuthResult {
  final bool success;
  final String? errorMessage;
  final String? userId;
  final String? email;
  final UserRole? role;

  /// `true` only for [AuthResult.cancelled] - the user backed out of a
  /// sign-in flow (e.g. closed the Google account picker) themselves. Never
  /// set by [AuthResult.failure]. Callers must show no error toast for this
  /// case - it is not a failure, just a no-op.
  final bool cancelled;

  const AuthResult._({
    required this.success,
    this.errorMessage,
    this.userId,
    this.email,
    this.role,
    this.cancelled = false,
  });

  factory AuthResult.success({
    required String userId,
    required String email,
    required UserRole role,
  }) {
    return AuthResult._(
      success: true,
      userId: userId,
      email: email,
      role: role,
    );
  }

  factory AuthResult.failure({required String errorMessage}) {
    return AuthResult._(success: false, errorMessage: errorMessage);
  }

  /// The user themselves backed out of a sign-in flow (e.g. dismissed the
  /// Google account picker) - not an error, never shown as one.
  factory AuthResult.cancelled() {
    return const AuthResult._(success: false, cancelled: true);
  }
}
