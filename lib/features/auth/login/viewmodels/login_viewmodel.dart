import 'package:flutter/material.dart';
import '../../../../core/models/auth/auth_result.dart';
import '../../repositories/auth_repository.dart';
import '../../services/remembered_login_store.dart';
import '../../../../app/viewmodels/auth_session_state.dart';

class LoginViewModel extends ChangeNotifier {
  final AuthRepository _authRepository;
  final AuthSessionState _authSessionState;
  final RememberedLoginStore _rememberedLoginStore;

  LoginViewModel(
    this._authRepository,
    this._authSessionState, {
    RememberedLoginStore? rememberedLoginStore,
  }) : _rememberedLoginStore = rememberedLoginStore ?? RememberedLoginStore() {
    _loadRememberedEmail();
  }

  String _email = '';
  String _password = '';
  bool _isRememberMeChecked = false;
  bool _isLoading = false;

  Future<void> _loadRememberedEmail() async {
    try {
      final savedEmail = await _rememberedLoginStore.getSavedEmail();
      // Guard against a race with the user already typing (or already
      // submitting) before this async load resolves - never clobber
      // in-progress input with a late-arriving stored value.
      if (savedEmail != null && savedEmail.isNotEmpty && _email.isEmpty) {
        _email = savedEmail;
        _isRememberMeChecked = true;
        notifyListeners();
      }
    } catch (_) {
      // Local-storage read failure just means no pre-filled email -
      // never block or crash the Login screen over this.
    }
  }

  String get email => _email;
  String get password => _password;
  bool get isRememberMeChecked => _isRememberMeChecked;
  bool get isLoading => _isLoading;

  void updateEmail(String val) {
    _email = val;
    notifyListeners();
  }

  void updatePassword(String val) {
    _password = val;
    notifyListeners();
  }

  void toggleRememberMe() {
    _isRememberMeChecked = !_isRememberMeChecked;
    notifyListeners();
  }

  bool _isValidEmail(String email) {
    final emailRegExp = RegExp(
      r"^[a-zA-Z0-9.!#$%&'*+/=?^_`{|}~-]+@[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?(?:\.[a-zA-Z0-9](?:[a-zA-Z0-9-]{0,61}[a-zA-Z0-9])?)*$",
    );
    return emailRegExp.hasMatch(email.trim());
  }

  Future<AuthResult> submitLogin() async {
    if (_email.isEmpty || !_isValidEmail(_email)) {
      return AuthResult.failure(errorMessage: 'Invalid email or password.');
    }
    if (_password.isEmpty) {
      return AuthResult.failure(errorMessage: 'Invalid email or password.');
    }

    _isLoading = true;
    notifyListeners();

    final result = await _authRepository.signIn(
      email: _email,
      password: _password,
    );

    if (result.success) {
      _authSessionState.setSession(result);
      try {
        if (_isRememberMeChecked) {
          await _rememberedLoginStore.saveEmail(_email.trim());
        } else {
          await _rememberedLoginStore.clearEmail();
        }
      } catch (_) {
        // Remember Me is a convenience, not a login-blocking requirement -
        // a local-storage write failure must never fail the sign-in itself.
      }
    }

    _isLoading = false;
    notifyListeners();

    return result;
  }
}
