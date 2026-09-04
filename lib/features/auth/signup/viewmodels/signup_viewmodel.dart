import 'package:flutter/material.dart';
import '../../repositories/auth_repository.dart';

enum SignupResult {
  success,
  invalidName,
  invalidEmail,
  invalidPhone,
  passwordTooWeak,
  passwordMismatch,
  termsNotAccepted,
  firebaseError,
}

class SignupViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;

  SignupViewModel(this._authRepository);

  bool _isLoading = false;
  bool _termsAccepted = false;
  String? _firebaseErrorMessage;

  bool get isLoading => _isLoading;
  bool get termsAccepted => _termsAccepted;

  /// Set only when [validateAndSignUp] returns [SignupResult.firebaseError];
  /// a clean, user-friendly message already mapped from the Firebase error.
  String? get firebaseErrorMessage => _firebaseErrorMessage;

  void toggleTermsAccepted(bool? value) {
    _termsAccepted = value ?? false;
    notifyListeners();
  }

  bool _isValidEmail(String email) {
    final emailRegExp = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
    );
    return emailRegExp.hasMatch(email);
  }

  /// The single source of truth for an acceptable phone number, matching the
  /// `users/{uid}.phone` Firestore rule exactly (Phase 8.12): a standard
  /// Pakistani local mobile number - exactly 11 digits, digits only,
  /// starting with `03` (e.g. `03001234567`). Spaces, `+92`, hyphens,
  /// brackets and letters are all rejected.
  static final RegExp _pakistaniMobile = RegExp(r'^03[0-9]{9}$');

  bool _isValidPhone(String phone) => _pakistaniMobile.hasMatch(phone);

  /// At least 8 characters, with at least one uppercase letter, one
  /// lowercase letter, one digit, and one special (non-alphanumeric)
  /// character.
  bool _isStrongPassword(String password) {
    if (password.length < 8) return false;
    final hasUppercase = RegExp(r'[A-Z]').hasMatch(password);
    final hasLowercase = RegExp(r'[a-z]').hasMatch(password);
    final hasDigit = RegExp(r'[0-9]').hasMatch(password);
    final hasSpecialChar = RegExp(r'[^A-Za-z0-9]').hasMatch(password);
    return hasUppercase && hasLowercase && hasDigit && hasSpecialChar;
  }

  Future<SignupResult> validateAndSignUp({
    required String name,
    required String email,
    required String phone,
    required String password,
    required String confirmPassword,
  }) async {
    // Phase 8.12: the `users/{uid}.displayName` rule requires a non-empty,
    // non-whitespace-only string of at most 100 characters - reject it
    // here so the user gets a clean message, never a Firebase
    // permission-denied on the profile write.
    if (name.trim().isEmpty || name.trim().length > 100) {
      return SignupResult.invalidName;
    }
    if (email.trim().isEmpty || !_isValidEmail(email.trim())) {
      return SignupResult.invalidEmail;
    }
    if (phone.trim().isEmpty || !_isValidPhone(phone.trim())) {
      return SignupResult.invalidPhone;
    }
    if (!_isStrongPassword(password)) {
      return SignupResult.passwordTooWeak;
    }
    if (password != confirmPassword) {
      return SignupResult.passwordMismatch;
    }
    if (!_termsAccepted) {
      return SignupResult.termsNotAccepted;
    }

    _isLoading = true;
    notifyListeners();

    final errorMessage = await _authRepository.signUp(
      email: email.trim(),
      password: password,
      displayName: name.trim(),
      phone: phone.trim(),
    );

    _isLoading = false;
    notifyListeners();

    if (errorMessage != null) {
      _firebaseErrorMessage = errorMessage;
      return SignupResult.firebaseError;
    }

    return SignupResult.success;
  }
}
