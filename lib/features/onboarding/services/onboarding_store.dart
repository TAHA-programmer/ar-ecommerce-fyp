import 'package:shared_preferences/shared_preferences.dart';

/// Tracks, on-device only, whether this installation has ever finished (or
/// skipped) the onboarding flow. Never mirrored to Firestore - onboarding
/// completion is a per-install concern, not a per-account one.
class OnboardingStore {
  static const _completedKey = 'has_completed_onboarding';

  Future<bool> hasCompletedOnboarding() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_completedKey) ?? false;
  }

  Future<void> markCompleted() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_completedKey, true);
  }
}
