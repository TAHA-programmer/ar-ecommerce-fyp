import 'package:google_sign_in/google_sign_in.dart';
import 'google_sign_in_service.dart';

/// Real [GoogleSignInService], wrapping `package:google_sign_in` v7's API.
///
/// v7 replaced the old `GoogleSignIn()` constructor + `.signIn()` shape with
/// a singleton (`GoogleSignIn.instance`) that must be `initialize()`d
/// exactly once before use, and an `.authenticate()` call that THROWS a
/// [GoogleSignInException] (never returns `null`) on cancellation - the
/// inverse of the old API. [signIn] re-normalises that back into this
/// service's own `null`-means-cancelled contract so
/// [FirebaseAuthRepository] never has to know which package version is
/// behind the seam.
///
/// No `serverClientId`/`clientId` is passed to [GoogleSignIn.initialize] -
/// on Android, `google_sign_in_android` reads the web OAuth client
/// (`oauth_client` with `client_type: 3`) directly out of
/// `google-services.json` once Google Sign-In has been enabled for this
/// project in the Firebase Console (that step is what CREATES that entry -
/// see the tracker for the exact console steps). Until that is done,
/// [initialize] itself throws a [GoogleSignInException] with
/// [GoogleSignInExceptionCode.clientConfigurationError] or
/// `providerConfigurationError`, mapped below to
/// [GoogleSignInFailureReason.configuration] - an expected, not a bug,
/// state for as long as the console step is outstanding.
class DeviceGoogleSignInService implements GoogleSignInService {
  final GoogleSignIn _googleSignIn;
  Future<void>? _initialization;

  DeviceGoogleSignInService({GoogleSignIn? googleSignIn})
    : _googleSignIn = googleSignIn ?? GoogleSignIn.instance;

  Future<void> _ensureInitialized() {
    // `initialize()` must be called exactly once per process - memoize the
    // Future itself (not just a bool flag) so two taps that race each other
    // both await the SAME initialization instead of one firing a second,
    // invalid call.
    return _initialization ??= _googleSignIn.initialize();
  }

  @override
  Future<GoogleSignInPayload?> signIn() async {
    try {
      await _ensureInitialized();
    } on GoogleSignInException catch (e) {
      // A failed initialize() must be retried on the next tap, not
      // permanently remembered as "already initialized".
      _initialization = null;
      throw _mapException(e);
    }

    final GoogleSignInAccount account;
    try {
      account = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) return null;
      throw _mapException(e);
    }

    final idToken = account.authentication.idToken;
    if (idToken == null || idToken.isEmpty) {
      throw const GoogleSignInFailure(
        GoogleSignInFailureReason.unavailable,
        'Google did not return a valid sign-in token.',
      );
    }
    return GoogleSignInPayload(idToken: idToken);
  }

  @override
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {
      // Best-effort only - see the interface doc comment.
    }
  }

  GoogleSignInFailure _mapException(GoogleSignInException e) {
    switch (e.code) {
      case GoogleSignInExceptionCode.clientConfigurationError:
      case GoogleSignInExceptionCode.providerConfigurationError:
        return GoogleSignInFailure(
          GoogleSignInFailureReason.configuration,
          'Google Sign-In is not set up correctly yet. '
                  '${e.description ?? ''}'
              .trim(),
        );
      case GoogleSignInExceptionCode.uiUnavailable:
      case GoogleSignInExceptionCode.interrupted:
        return const GoogleSignInFailure(
          GoogleSignInFailureReason.unavailable,
          'Google Sign-In could not be started. Please try again.',
        );
      case GoogleSignInExceptionCode.canceled:
        // Never reached - callers handle `canceled` before calling this.
        return const GoogleSignInFailure(
          GoogleSignInFailureReason.unknown,
          'Sign-in was cancelled.',
        );
      default:
        return const GoogleSignInFailure(
          GoogleSignInFailureReason.unknown,
          'Something went wrong with Google Sign-In. Please try again.',
        );
    }
  }
}
