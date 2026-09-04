import 'user_role.dart';

class AuthResult {
  final bool success;
  final String? errorMessage;
  final String? userId;
  final String? email;
  final UserRole? role;

  const AuthResult._({
    required this.success,
    this.errorMessage,
    this.userId,
    this.email,
    this.role,
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
}
