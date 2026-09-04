import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/models/auth/auth_result.dart';
import '../../../core/models/auth/user_role.dart';
import '../../profile/repositories/user_profile_repository.dart';
import '../../profile/repositories/firestore_user_profile_repository.dart';
import 'auth_repository.dart';

const String _kGenericAuthError = 'Something went wrong. Please try again.';

class FirebaseAuthRepository implements AuthRepository {
  final FirebaseAuth _firebaseAuth;
  final UserProfileRepository _userProfileRepository;

  FirebaseAuthRepository({
    FirebaseAuth? firebaseAuth,
    UserProfileRepository? userProfileRepository,
  }) : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance,
       _userProfileRepository =
           userProfileRepository ?? FirestoreUserProfileRepository();

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

  @override
  Future<void> signOut() => _firebaseAuth.signOut();

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
