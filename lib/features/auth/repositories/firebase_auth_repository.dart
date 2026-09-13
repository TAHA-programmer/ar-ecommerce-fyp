import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/models/auth/auth_result.dart';
import '../../../core/models/auth/user_role.dart';
import '../../profile/repositories/user_profile_repository.dart';
import '../../profile/repositories/firestore_user_profile_repository.dart';
import '../services/google_sign_in_service.dart';
import '../services/device_google_sign_in_service.dart';
import 'auth_repository.dart';

const String _kGenericAuthError = 'Something went wrong. Please try again.';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _firebaseAuth;
  final UserProfileRepository _userProfileRepository;
  final GoogleSignInService _googleSignInService;

  FirebaseAuthRepository({
    FirebaseAuth? firebaseAuth,
    UserProfileRepository? userProfileRepository,
    GoogleSignInService? googleSignInService,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _userProfileRepository =
           userProfileRepository ?? FirestoreUserProfileRepository(),
       _googleSignInService =
           googleSignInService ?? DeviceGoogleSignInService();

  @override
  Future<AuthResult> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final credential = await _firebaseAuth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) {
        return AuthResult.failure(errorMessage: _kGenericAuthError);
      }
      return AuthResult.success(
        userId: user.uid,
        email: user.email ?? email.trim(),
        role: await _resolveRole(user),
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(errorMessage: _mapAuthError(e));
    } catch (_) {
      return AuthResult.failure(errorMessage: _kGenericAuthError);
    }
  }

  @override
  Future<String?> signUp({
    required String email,
    required String password,
    required String displayName,
    required String phone,
  }) async {
    final UserCredential credential;
    try {
      credential = await _firebaseAuth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e);
    } catch (_) {
      return _kGenericAuthError;
    }

    final user = credential.user;
    if (user == null) {
      return _kGenericAuthError;
    }

    try {
      await _userProfileRepository.createProfile(
        uid: user.uid,
        email: user.email ?? email.trim(),
        displayName: displayName.trim(),
        phone: phone.trim(),
      );
    } catch (_) {
      // Narrow recovery: never leave an orphaned Auth account with no
      // profile document. Best-effort delete the account we just created
      // (no retry queue, no background repair job - out of scope for this
      // phase) and surface a single clean message asking the user to try
      // again. If the delete itself also fails (rare - e.g. the network
      // drops between the two calls), the account is still signed out
      // below so the app is never left mid-session; a truly orphaned
      // account in that double-failure case is an accepted edge case.
      try {
        await user.delete();
      } catch (_) {
        // See comment above - accepted edge case, nothing further to do.
      }
      try {
        await _firebaseAuth.signOut();
      } catch (_) {
        // Best-effort only; there is no session left to protect either way.
      }
      return 'Something went wrong creating your account. Please try again.';
    }

    // Firebase automatically signs the new user in. The app's existing
    // sign-up UX returns the user to Login to sign in explicitly, so sign
    // back out immediately to match that flow exactly (no session/UI
    // change here).
    await _firebaseAuth.signOut();
    return null;
  }

  /// `account-exists-with-different-credential` (an email already registered
  /// via a different provider) is mapped below in [_mapAuthError] to a fixed
  /// "sign in with your password instead" message rather than looking up
  /// which provider they actually used - `firebase_auth`'s
  /// `fetchSignInMethodsForEmail` was removed from the SDK entirely (Google's
  /// 2023+ email-enumeration-protection hardening), so that lookup is no
  /// longer possible, and this app only ever offers one other method
  /// (email/password) regardless. Deliberately does **not** attempt silent/
  /// automatic account linking from this unauthenticated error state - that
  /// would mean trusting an unverified Google credential to merge into an
  /// existing account before the caller has proven they own it. Account
  /// linking (`currentUser.linkWithCredential`), if wanted, belongs behind a
  /// separate, explicit, already-authenticated action - out of scope for
  /// this pass; not implemented.
  @override
  Future<AuthResult> signInWithGoogle() async {
    final GoogleSignInPayload? payload;
    try {
      payload = await _googleSignInService.signIn();
    } on GoogleSignInFailure catch (e) {
      return AuthResult.failure(errorMessage: e.message);
    } catch (_) {
      return AuthResult.failure(errorMessage: _kGenericAuthError);
    }
    if (payload == null) {
      // The user closed the account picker themselves - not an error.
      return AuthResult.cancelled();
    }

    final UserCredential credential;
    try {
      credential = await _firebaseAuth.signInWithCredential(
        GoogleAuthProvider.credential(idToken: payload.idToken),
      );
    } on FirebaseAuthException catch (e) {
      return AuthResult.failure(errorMessage: _mapAuthError(e));
    } catch (_) {
      return AuthResult.failure(errorMessage: _kGenericAuthError);
    }

    final user = credential.user;
    if (user == null) {
      return AuthResult.failure(errorMessage: _kGenericAuthError);
    }

    await _ensureProfileExists(user);

    return AuthResult.success(
      userId: user.uid,
      email: user.email ?? '',
      role: await _resolveRole(user),
    );
  }

  /// Idempotently ensures [user] has a `users/{uid}` Firestore profile,
  /// creating one ONLY when [user] is Google-authenticated (checked via
  /// `user.providerData` - the standard, real signal for which providers are
  /// linked to this identity) and no profile exists yet. Never touches or
  /// overwrites an existing profile - a returning Google user's profile
  /// (and any edits they made to it) is left exactly as-is.
  ///
  /// **Recovery guarantee (security recheck 2026-09-13):** called from BOTH
  /// [signInWithGoogle] (a fresh sign-in) AND every [authStateChanges]
  /// emission (an app restart / persisted-session resume). A profile-write
  /// failure right after a successful Google sign-in therefore self-heals
  /// on the very next app launch or auth-state resolution, not only on a
  /// second manual sign-in attempt - the user is never left stranded in a
  /// signed-in-but-profile-less state with no path back to a working
  /// profile (an `.update()`-based Edit Profile save would otherwise fail
  /// forever on a genuinely missing document). A write failure here is
  /// still deliberately non-fatal to the caller either way: unlike [signUp]
  /// (which has no session yet to protect), this user is already
  /// authenticated, so the safe move is to let them continue and retry
  /// automatically, never to strand or sign them back out over it.
  ///
  /// For a non-Google identity (currently only `password`) a missing
  /// profile is left alone - `signUp` always creates one before any real
  /// session exists, so this should never be reached for that provider, and
  /// this method has no valid phone value to invent for it. `role` is
  /// always `'customer'` (see `createProfile`'s own doc comment) - nothing
  /// here ever reads a role from any provider's profile data.
  Future<void> _ensureProfileExists(User user) async {
    final isGoogleUser = user.providerData.any(
      (info) => info.providerId == 'google.com',
    );
    if (!isGoogleUser) return;

    try {
      final existingProfile = await _userProfileRepository.getProfile(user.uid);
      if (existingProfile != null) return;
      final displayName = user.displayName?.trim() ?? '';
      await _userProfileRepository.createProfile(
        uid: user.uid,
        email: user.email ?? '',
        displayName: displayName.isNotEmpty ? displayName : 'TWin AR Customer',
        // Google never supplies a phone number. Left empty - the Firestore
        // `create` rule accepts an empty phone only for a request whose ID
        // token proves `sign_in_provider == 'google.com'`; the customer
        // fills in a real one later via Edit Profile, at which point the
        // same Pakistani-mobile validation as every other account applies.
        phone: '',
      );
    } catch (_) {
      // Non-fatal - see the doc comment above.
    }
  }

  @override
  Future<void> signOut() async {
    await _firebaseAuth.signOut();
    // Best-effort: clears the on-device Google session so a future
    // "Continue with Google" shows the account picker again instead of
    // silently reusing whichever account was last used. Never allowed to
    // block or fail logout itself - see the service's own doc comment.
    await _googleSignInService.signOut();
  }

  @override
  Future<String?> sendPasswordResetEmail({required String email}) async {
    try {
      await _firebaseAuth.sendPasswordResetEmail(email: email.trim());
      return null;
    } on FirebaseAuthException catch (e) {
      return _mapAuthError(e);
    } catch (_) {
      return _kGenericAuthError;
    }
  }

  @override
  Stream<AuthResult?> authStateChanges() {
    return _firebaseAuth.authStateChanges().asyncMap((user) async {
      if (user == null) return null;
      // Security recheck (2026-09-13): also runs on every persisted-session
      // resume (app restart), not only a fresh sign-in - see
      // `_ensureProfileExists`'s doc comment for why this closes the
      // "profile-write failed, user permanently stranded" gap. A pure no-op
      // (no Firestore call at all) for every non-Google session; for a
      // Google session it is one cheap profile read, and a write only on
      // the rare occasion one is still missing.
      await _ensureProfileExists(user);
      return AuthResult.success(
        userId: user.uid,
        email: user.email ?? '',
        role: await _resolveRole(user),
      );
    });
  }

  /// The real authorization source: the Firebase ID token's `role` custom
  /// claim, never `users/{uid}.role` (a UI-convenience mirror only - see
  /// `UserProfileModel`'s doc comment) and never any client-side/email
  /// heuristic. A missing claim, a non-`superAdmin` claim, or a failure to
  /// read the token at all all safely resolve to [UserRole.customer] - the
  /// same default a brand-new signup gets, so there is no privileged
  /// fallback to abuse.
  ///
  /// `forceRefresh: true` is used so a token cached before a claim was set
  /// (e.g. the one-time Super Admin bootstrap script ran while this device
  /// still held an older token) is never trusted stale. This runs once per
  /// sign-in/auth-state transition, not on a timer - not polling.
  Future<UserRole> _resolveRole(User user) async {
    try {
      final tokenResult = await user.getIdTokenResult(true);
      final claim = tokenResult.claims?['role'];
      return claim == 'superAdmin' ? UserRole.superAdmin : UserRole.customer;
    } catch (_) {
      return UserRole.customer;
    }
  }

  /// Maps current (non-deprecated) [FirebaseAuthException] codes to clean,
  /// user-friendly messages. Never surfaces raw Firebase exception text.
  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'user-disabled':
        return 'This account has been disabled. Please contact support.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        // Deliberately identical to avoid revealing which part was wrong.
        return 'Invalid email or password.';
      case 'email-already-in-use':
        return 'An account already exists with this email.';
      case 'account-exists-with-different-credential':
        // The only other sign-in method this app offers is email/password,
        // so this is always accurate without needing to enumerate methods
        // (the SDK no longer exposes that lookup at all - see the doc
        // comment on `signInWithGoogle`'s error handling).
        return 'An account already exists with this email using a '
            'password. Please sign in with your email and password instead.';
      case 'weak-password':
        return 'Password is too weak. Please choose a stronger password.';
      case 'operation-not-allowed':
        return 'This sign-in method is currently unavailable.';
      case 'network-request-failed':
        return 'Network error. Please check your connection and try again.';
      case 'too-many-requests':
        return 'Too many attempts. Please try again later.';
      default:
        return _kGenericAuthError;
    }
  }
}
