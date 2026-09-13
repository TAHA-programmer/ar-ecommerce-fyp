/// The tokens [GoogleSignInService.signIn] hands back so
/// [FirebaseAuthRepository] can build a [GoogleAuthProvider] credential.
/// Deliberately holds nothing else (no email/displayName/photo) - once
/// `signInWithCredential` succeeds, Firebase's own [User] is the single
/// source of truth for that identity data.
class GoogleSignInPayload {
  final String idToken;
  final String? accessToken;

  const GoogleSignInPayload({required this.idToken, this.accessToken});
}

/// Why a genuine Google sign-in attempt did not produce a payload -
/// deliberately distinct from "the user cancelled" (see
/// [GoogleSignInService.signIn]'s doc comment), which is not an error at
/// all. Mirrors [ProductVtoMetadata]/[ProductArMetadata]'s own pattern of a
/// closed, explainable reason set rather than a raw rethrown platform
/// exception.
enum GoogleSignInFailureReason {
  /// No network, or the provider timed out.
  network,

  /// The app/Firebase project is not correctly configured for Google
  /// Sign-In yet (Google not enabled in Firebase Console, SHA-1 not
  /// registered, or `google-services.json` predates that setup).
  configuration,

  /// The sign-in UI could not be shown, or was interrupted for a reason
  /// other than the user choosing to cancel.
  unavailable,

  unknown,
}

class GoogleSignInFailure implements Exception {
  final GoogleSignInFailureReason reason;
  final String message;

  const GoogleSignInFailure(this.reason, this.message);

  @override
  String toString() => 'GoogleSignInFailure($reason, $message)';
}

/// Seam between [FirebaseAuthRepository] and the platform Google Sign-In
/// SDK - the same "wrap the native/platform capability behind a narrow
/// interface" pattern this codebase already uses for
/// `DeviceImagePickerService`/`RoomArCapabilityService`. Lets the repository
/// (and its tests) never touch `package:google_sign_in` directly.
abstract class GoogleSignInService {
  /// Runs the Google account-picker flow. Returns `null` when the user
  /// cancelled - a normal, silent outcome, never an error toast. Throws
  /// [GoogleSignInFailure] for a genuine failure worth surfacing.
  Future<GoogleSignInPayload?> signIn();

  /// Best-effort only - clears the on-device Google session so a later
  /// sign-in shows the account picker again instead of silently reusing the
  /// last account. Never the source of truth for the app's own session
  /// (Firebase sign-out is); a failure here must never block logout.
  Future<void> signOut();
}
