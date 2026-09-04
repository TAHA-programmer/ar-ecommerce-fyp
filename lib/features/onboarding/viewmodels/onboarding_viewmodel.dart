import 'package:flutter/foundation.dart';
import '../services/onboarding_store.dart';

class OnboardingViewModel extends ChangeNotifier {
  final OnboardingStore _onboardingStore;

  OnboardingViewModel({OnboardingStore? onboardingStore})
    : _onboardingStore = onboardingStore ?? OnboardingStore();

  int _currentPage = 0;
  final int totalPages = 3;

  int get currentPage => _currentPage;
  bool get isFirstPage => _currentPage == 0;
  bool get isLastPage => _currentPage == totalPages - 1;

  void onPageChanged(int index) {
    _currentPage = index;
    notifyListeners();
  }

  /// Marks this installation as having finished onboarding (via Skip or
  /// completing the final page) so it is never shown again after logout.
  Future<void> markOnboardingComplete() async {
    try {
      await _onboardingStore.markCompleted();
    } catch (_) {
      // Local-storage write failure just means onboarding may show again
      // next launch - never block navigation to Login over this.
    }
  }
}
