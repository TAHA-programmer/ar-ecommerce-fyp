import 'package:twin_ar/features/auth/services/google_sign_in_service.dart';

/// Test-only [GoogleSignInService] double - never touches the platform
/// Google Sign-In SDK. Configure exactly one of [nextPayload]/[nextFailure]
/// (or neither, for "user cancelled") before calling [signIn].
class FakeGoogleSignInService implements GoogleSignInService {
  GoogleSignInPayload? nextPayload;
  GoogleSignInFailure? nextFailure;
  bool signOutCalled = false;
  int signInCallCount = 0;

  @override
  Future<GoogleSignInPayload?> signIn() async {
    signInCallCount++;
    final failure = nextFailure;
    if (failure != null) throw failure;
    return nextPayload;
  }

  @override
  Future<void> signOut() async {
    signOutCalled = true;
  }
}
