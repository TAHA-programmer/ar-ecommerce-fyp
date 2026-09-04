import 'package:flutter/material.dart';
import 'dart:async';
import '../../../app/viewmodels/auth_session_state.dart';
import '../../onboarding/services/onboarding_store.dart';

enum SplashState { loading, complete }

class SplashViewModel extends ChangeNotifier {
  final AuthSessionState _authSessionState;
  final OnboardingStore _onboardingStore;

  SplashViewModel(this._authSessionState, {OnboardingStore? onboardingStore})
    : _onboardingStore = onboardingStore ?? OnboardingStore();

  SplashState _state = SplashState.loading;
  SplashState get state => _state;

  bool _hasCompletedOnboarding = false;
  bool get hasCompletedOnboarding => _hasCompletedOnboarding;

  bool get isAuthenticated => _authSessionState.isAuthenticated;
  bool get isSuperAdmin => _authSessionState.isSuperAdmin;

  void initialize() {
    // Wait for the branding timer, Firebase's first auth-state
    // determination, and the on-device onboarding flag together, so
    // startup never routes to the wrong screen while any of them is
    // still being resolved.
    Future.wait([
      Future.delayed(const Duration(milliseconds: 2500)),
      _authSessionState.ready,
      _loadOnboardingStatus(),
    ]).then((_) {
      _state = SplashState.complete;
      notifyListeners();
    });
  }

  Future<void> _loadOnboardingStatus() async {
    try {
      _hasCompletedOnboarding = await _onboardingStore.hasCompletedOnboarding();
    } catch (_) {
      // Safe default: treat as not completed so onboarding is shown rather
      // than silently skipped on a local-storage read failure.
      _hasCompletedOnboarding = false;
    }
  }
}
