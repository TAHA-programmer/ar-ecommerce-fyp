import 'package:flutter/material.dart';
import '../../repositories/auth_repository.dart';

enum ForgotPasswordResult { success, emptyEmail, invalidEmail, failure }

class ForgotPasswordViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  ForgotPasswordViewModel(this._authRepository);

  bool _isLoading = false;
  String? _failureMessage;

  bool get isLoading => _isLoading;

  /// Set only when [sendResetLink] returns [ForgotPasswordResult.failure].
  String? get failureMessage => _failureMessage;

  bool _isValidEmail(String email) {
    final emailRegExp = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
    );
    return emailRegExp.hasMatch(email);
  }

  Future<ForgotPasswordResult> sendResetLink({required String email}) async {
    final trimmedEmail = email.trim();
    if (trimmedEmail.isEmpty) {
      return ForgotPasswordResult.emptyEmail;
    }
    if (!_isValidEmail(trimmedEmail)) {
      return ForgotPasswordResult.invalidEmail;
    }

    _isLoading = true;
    notifyListeners();

    final errorMessage = await _authRepository.sendPasswordResetEmail(
      email: trimmedEmail,
    );

    _isLoading = false;
    notifyListeners();

    if (errorMessage != null) {
      _failureMessage = errorMessage;
      return ForgotPasswordResult.failure;
    }

    return ForgotPasswordResult.success;
  }
}
