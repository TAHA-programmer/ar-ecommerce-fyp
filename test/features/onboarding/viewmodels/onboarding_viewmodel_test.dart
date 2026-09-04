import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:twin_ar/features/onboarding/services/onboarding_store.dart';
import 'package:twin_ar/features/onboarding/viewmodels/onboarding_viewmodel.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('OnboardingViewModel - onboarding persistence', () {
    test('markOnboardingComplete persists the local flag', () async {
      final viewModel = OnboardingViewModel();

      expect(await OnboardingStore().hasCompletedOnboarding(), isFalse);

      await viewModel.markOnboardingComplete();

      expect(await OnboardingStore().hasCompletedOnboarding(), isTrue);
    });

    test('page navigation state is unaffected by onboarding persistence', () {
      final viewModel = OnboardingViewModel();

      expect(viewModel.currentPage, 0);
      expect(viewModel.isFirstPage, isTrue);
      expect(viewModel.isLastPage, isFalse);

      viewModel.onPageChanged(2);

      expect(viewModel.currentPage, 2);
      expect(viewModel.isLastPage, isTrue);
    });
  });
}
