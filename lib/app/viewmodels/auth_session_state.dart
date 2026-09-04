import 'dart:async';
import 'package:flutter/material.dart';
import '../../core/models/auth/user_role.dart';
import '../../core/models/auth/auth_result.dart';
import '../../features/auth/repositories/auth_repository.dart';

/// Shared session source of truth, mirroring the [CommerceDatabase]/
/// [MockCommerceDatabase] "single reactive source" pattern.
///
/// When constructed with an [AuthRepository] (the production path, wired in
/// `app_providers.dart`), it subscribes to [AuthRepository.authStateChanges]
/// and keeps itself in sync automatically - this is what makes a
/// Firebase-authenticated user "stay authenticated" across app restarts and
/// lets Splash wait for [ready] before deciding where to route. The
/// [AuthRepository] parameter is optional and defaults to `null` so the many
/// existing tests that construct `AuthSessionState()` directly (with no
/// interest in auth-state reactivity) continue to work unchanged - manual
/// [setSession]/[clearSession] calls behave exactly as before either way.
class AuthSessionState extends ChangeNotifier {
  final AuthRepository? _authRepository;
  StreamSubscription<AuthResult?>? _authStateSubscription;
  final Completer<void> _readyCompleter = Completer<void>();

  String? _userId;
  String? _email;
  UserRole? _role;

  AuthSessionState([this._authRepository]) {
    final repository = _authRepository;
    if (repository == null) {
      _readyCompleter.complete();
      return;
    }
    _authStateSubscription = repository.authStateChanges().listen(
      (result) {
        if (result != null && result.success) {
          setSession(result);
        } else {
          clearSession();
        }
        if (!_readyCompleter.isCompleted) _readyCompleter.complete();
      },
      // Defensive: an auth-state stream error must never leave the app
      // stuck on a perpetual loading screen. Fall back to "not
      // authenticated" and let Splash proceed to Onboarding/Login.
      onError: (_) {
        clearSession();
        if (!_readyCompleter.isCompleted) _readyCompleter.complete();
      },
    );
  }

  /// Completes once the first auth-state determination has been made (or
  /// immediately, if no [AuthRepository] was provided). Splash awaits this
  /// alongside its branding timer so startup never shows Login while
  /// Firebase is still resolving a persisted session.
  Future<void> get ready => _readyCompleter.future;

  String? get userId => _userId;
  String? get email => _email;
  UserRole? get role => _role;

  bool get isAuthenticated => _userId != null && _role != null;
  bool get isCustomer => isAuthenticated && _role == UserRole.customer;
  bool get isSuperAdmin => isAuthenticated && _role == UserRole.superAdmin;

  void setSession(AuthResult authResult) {
    if (authResult.success &&
        authResult.userId != null &&
        authResult.role != null) {
      _userId = authResult.userId;
      _email = authResult.email;
      _role = authResult.role;
      notifyListeners();
    }
  }

  void clearSession() {
    _userId = null;
    _email = null;
    _role = null;
    notifyListeners();
  }

  @override
  void dispose() {
    _authStateSubscription?.cancel();
    super.dispose();
  }
}
