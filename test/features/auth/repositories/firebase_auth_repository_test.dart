import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/features/auth/repositories/firebase_auth_repository.dart';
import 'package:twin_ar/features/auth/services/google_sign_in_service.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/repositories/user_profile_repository.dart';

import '../support/fake_google_sign_in_service.dart';

/// Wraps [MockUserProfileRepository] and records the uid passed to
/// [createProfile] - needed because `firebase_auth_mocks`'
/// `createUserWithEmailAndPassword` generates its own random uid rather
/// than honoring any uid configured on the [MockFirebaseAuth] constructor.
class _RecordingUserProfileRepository implements UserProfileRepository {
  final _delegate = MockUserProfileRepository();
  String? lastCreatedUid;

  @override
  Future<void> createProfile({
    required String uid,
    required String email,
    required String displayName,
    required String phone,
  }) async {
    lastCreatedUid = uid;
    await _delegate.createProfile(
      uid: uid,
      email: email,
      displayName: displayName,
      phone: phone,
    );
  }

  @override
  Future<UserProfileModel?> getProfile(String uid) => _delegate.getProfile(uid);

  @override
  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String phone,
  }) =>
      _delegate.updateProfile(uid: uid, displayName: displayName, phone: phone);

  @override
  Future<void> updateAvatarStoragePath({
    required String uid,
    required String? avatarStoragePath,
  }) => _delegate.updateAvatarStoragePath(
    uid: uid,
    avatarStoragePath: avatarStoragePath,
  );
}

/// Throws on every call - used to exercise the signup rollback path.
class _ThrowingUserProfileRepository implements UserProfileRepository {
  @override
  Future<void> createProfile({
    required String uid,
    required String email,
    required String displayName,
    required String phone,
  }) async {
    throw Exception('simulated Firestore failure');
  }

  @override
  Future<UserProfileModel?> getProfile(String uid) async => null;

  @override
  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String phone,
  }) async {}

  @override
  Future<void> updateAvatarStoragePath({
    required String uid,
    required String? avatarStoragePath,
  }) async {}
}

/// Fails [createProfile] exactly [failCreatesRemaining] times, then delegates
/// normally - simulates a transient Firestore outage that clears up by the
/// next attempt. Also counts every call, for asserting a call did/did not
/// happen at all (distinct from asserting on the outcome, which a silently-
/// caught failure would otherwise hide).
class _FlakyThenWorkingUserProfileRepository implements UserProfileRepository {
  final _delegate = MockUserProfileRepository();
  int failCreatesRemaining;
  int createProfileCallCount = 0;
  int getProfileCallCount = 0;

  _FlakyThenWorkingUserProfileRepository({this.failCreatesRemaining = 0});

  @override
  Future<void> createProfile({
    required String uid,
    required String email,
    required String displayName,
    required String phone,
  }) async {
    createProfileCallCount++;
    if (failCreatesRemaining > 0) {
      failCreatesRemaining--;
      throw Exception('simulated transient Firestore failure');
    }
    await _delegate.createProfile(
      uid: uid,
      email: email,
      displayName: displayName,
      phone: phone,
    );
  }

  @override
  Future<UserProfileModel?> getProfile(String uid) {
    getProfileCallCount++;
    return _delegate.getProfile(uid);
  }

  @override
  Future<void> updateProfile({
    required String uid,
    required String displayName,
    required String phone,
  }) =>
      _delegate.updateProfile(uid: uid, displayName: displayName, phone: phone);

  @override
  Future<void> updateAvatarStoragePath({
    required String uid,
    required String? avatarStoragePath,
  }) => _delegate.updateAvatarStoragePath(
    uid: uid,
    avatarStoragePath: avatarStoragePath,
  );
}

/// A [MockUser] whose `providerData` genuinely includes `google.com` - the
/// real signal `_ensureProfileExists` checks. `firebase_auth_mocks`'
/// `signInWithCredential` does not inspect the credential it is given, so a
/// plain `MockUser(...)` has NO provider data unless explicitly linked here
/// via the library's own public `linkWithProvider` API.
Future<MockUser> _googleMockUser({
  required String uid,
  required String email,
  String? displayName,
}) async {
  final user = MockUser(uid: uid, email: email, displayName: displayName);
  await user.linkWithProvider(GoogleAuthProvider());
  return user;
}

void main() {
  group('FirebaseAuthRepository - signIn role resolution', () {
    test('no custom claim resolves to customer', () async {
      final mockAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'uid-123', email: 'shopper@example.com'),
      );
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final result = await repository.signIn(
        email: 'shopper@example.com',
        password: 'Password123!',
      );

      expect(result.success, isTrue);
      expect(result.userId, 'uid-123');
      expect(result.role, UserRole.customer);
    });

    test('role:customer custom claim resolves to customer', () async {
      final mockAuth = MockFirebaseAuth(
        mockUser: MockUser(
          uid: 'uid-123',
          email: 'shopper@example.com',
          customClaim: {'role': 'customer'},
        ),
      );
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final result = await repository.signIn(
        email: 'shopper@example.com',
        password: 'Password123!',
      );

      expect(result.role, UserRole.customer);
    });

    test('role:superAdmin custom claim resolves to superAdmin', () async {
      final mockAuth = MockFirebaseAuth(
        mockUser: MockUser(
          uid: 'uid-admin',
          email: 'admin@example.com',
          customClaim: {'role': 'superAdmin'},
        ),
      );
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final result = await repository.signIn(
        email: 'admin@example.com',
        password: 'Password123!',
      );

      expect(result.role, UserRole.superAdmin);
    });

    test(
      'a malformed/unexpected claim value safely falls back to customer',
      () async {
        final mockAuth = MockFirebaseAuth(
          mockUser: MockUser(
            uid: 'uid-weird',
            email: 'weird@example.com',
            customClaim: {'role': 'not-a-real-role'},
          ),
        );
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: MockUserProfileRepository(),
        );

        final result = await repository.signIn(
          email: 'weird@example.com',
          password: 'Password123!',
        );

        expect(result.role, UserRole.customer);
      },
    );
  });

  group('FirebaseAuthRepository - signIn', () {
    test('maps invalid-email to a clean message', () async {
      final mockAuth = MockFirebaseAuth();
      whenCalling(
        Invocation.method(#signInWithEmailAndPassword, null),
      ).on(mockAuth).thenThrow(FirebaseAuthException(code: 'invalid-email'));
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final result = await repository.signIn(
        email: 'not-an-email',
        password: 'x',
      );

      expect(result.success, isFalse);
      expect(result.errorMessage, 'Please enter a valid email address.');
    });

    test(
      'maps wrong-password/user-not-found/invalid-credential to the same generic message',
      () async {
        for (final code in [
          'wrong-password',
          'user-not-found',
          'invalid-credential',
        ]) {
          final mockAuth = MockFirebaseAuth();
          whenCalling(
            Invocation.method(#signInWithEmailAndPassword, null),
          ).on(mockAuth).thenThrow(FirebaseAuthException(code: code));
          final repository = FirebaseAuthRepository(
            firebaseAuth: mockAuth,
            userProfileRepository: MockUserProfileRepository(),
          );

          final result = await repository.signIn(
            email: 'test@example.com',
            password: 'wrong',
          );

          expect(result.success, isFalse);
          expect(
            result.errorMessage,
            'Invalid email or password.',
            reason: 'code=$code should not leak which part was wrong',
          );
        }
      },
    );

    test('maps user-disabled to a clean message', () async {
      final mockAuth = MockFirebaseAuth();
      whenCalling(
        Invocation.method(#signInWithEmailAndPassword, null),
      ).on(mockAuth).thenThrow(FirebaseAuthException(code: 'user-disabled'));
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final result = await repository.signIn(
        email: 'test@example.com',
        password: 'x',
      );

      expect(
        result.errorMessage,
        'This account has been disabled. Please contact support.',
      );
    });

    test('maps network-request-failed to a clean message', () async {
      final mockAuth = MockFirebaseAuth();
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(mockAuth)
          .thenThrow(FirebaseAuthException(code: 'network-request-failed'));
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final result = await repository.signIn(
        email: 'test@example.com',
        password: 'x',
      );

      expect(
        result.errorMessage,
        'Network error. Please check your connection and try again.',
      );
    });

    test('maps an unrecognized code to the generic fallback message', () async {
      final mockAuth = MockFirebaseAuth();
      whenCalling(Invocation.method(#signInWithEmailAndPassword, null))
          .on(mockAuth)
          .thenThrow(FirebaseAuthException(code: 'some-unmapped-code'));
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final result = await repository.signIn(
        email: 'test@example.com',
        password: 'x',
      );

      expect(result.errorMessage, 'Something went wrong. Please try again.');
      // Never the raw Firebase text.
      expect(result.errorMessage, isNot(contains('FirebaseAuthException')));
    });
  });

  group('FirebaseAuthRepository - signUp', () {
    test(
      'success creates the Firestore profile, returns null and signs back out',
      () async {
        final mockAuth = MockFirebaseAuth();
        final profileRepository = _RecordingUserProfileRepository();
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: profileRepository,
        );

        final error = await repository.signUp(
          email: 'new@example.com',
          password: 'Password123!',
          displayName: 'New User',
          phone: '1234567890',
        );

        expect(error, isNull);
        expect(
          mockAuth.currentUser,
          isNull,
          reason:
              'signUp must sign back out to match the existing "return to '
              'Login" UX; Firebase auto-signs-in on account creation',
        );

        expect(profileRepository.lastCreatedUid, isNotNull);
        final profile = await profileRepository.getProfile(
          profileRepository.lastCreatedUid!,
        );
        expect(profile, isNotNull);
        expect(profile!.email, 'new@example.com');
        expect(profile.displayName, 'New User');
        expect(profile.phone, '1234567890');
        expect(profile.role, 'customer');
      },
    );

    test('a Firestore profile-creation failure rolls back the auth account and '
        'returns a clean error - never a silently incomplete signup', () async {
      final mockAuth = MockFirebaseAuth(
        mockUser: MockUser(uid: 'uid-broken', email: 'broken@example.com'),
      );
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: _ThrowingUserProfileRepository(),
      );

      final error = await repository.signUp(
        email: 'broken@example.com',
        password: 'Password123!',
        displayName: 'Broken User',
        phone: '1234567890',
      );

      expect(error, isNotNull);
      expect(error, isNot(contains('Exception')));
      expect(
        mockAuth.currentUser,
        isNull,
        reason:
            'the account must never be left in a signed-in, '
            'profile-less state after a rollback',
      );
    });

    test('maps email-already-in-use to a clean message', () async {
      final mockAuth = MockFirebaseAuth();
      whenCalling(Invocation.method(#createUserWithEmailAndPassword, null))
          .on(mockAuth)
          .thenThrow(FirebaseAuthException(code: 'email-already-in-use'));
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final error = await repository.signUp(
        email: 'taken@example.com',
        password: 'Password123!',
        displayName: 'Taken User',
        phone: '1234567890',
      );

      expect(error, 'An account already exists with this email.');
    });

    test('maps weak-password to a clean message', () async {
      final mockAuth = MockFirebaseAuth();
      whenCalling(
        Invocation.method(#createUserWithEmailAndPassword, null),
      ).on(mockAuth).thenThrow(FirebaseAuthException(code: 'weak-password'));
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final error = await repository.signUp(
        email: 'test@example.com',
        password: 'weak',
        displayName: 'Weak Password User',
        phone: '1234567890',
      );

      expect(error, 'Password is too weak. Please choose a stronger password.');
    });
  });

  group('FirebaseAuthRepository - signInWithGoogle', () {
    test(
      'first-time Google user: creates a customer profile with an empty phone, never overwrites anything',
      () async {
        final mockAuth = MockFirebaseAuth(
          mockUser: await _googleMockUser(
            uid: 'google-uid-new',
            email: 'newgoogle@example.com',
            displayName: 'New Googler',
          ),
        );
        final googleSignIn = FakeGoogleSignInService()
          ..nextPayload = const GoogleSignInPayload(idToken: 'fake-id-token');
        final profileRepository = _RecordingUserProfileRepository();
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: profileRepository,
          googleSignInService: googleSignIn,
        );

        final result = await repository.signInWithGoogle();

        expect(result.success, isTrue);
        expect(result.userId, 'google-uid-new');
        expect(result.role, UserRole.customer);

        final profile = await profileRepository.getProfile('google-uid-new');
        expect(profile, isNotNull);
        expect(profile!.email, 'newgoogle@example.com');
        expect(profile.displayName, 'New Googler');
        expect(
          profile.phone,
          '',
          reason: 'Google never supplies a phone number',
        );
        expect(profile.role, 'customer');
      },
    );

    test(
      'a Google display name that is empty/whitespace falls back to a non-empty default '
      '(the displayName Firestore rule rejects an empty string)',
      () async {
        final mockAuth = MockFirebaseAuth(
          mockUser: await _googleMockUser(
            uid: 'google-uid-noname',
            email: 'noname@example.com',
            displayName: '   ',
          ),
        );
        final googleSignIn = FakeGoogleSignInService()
          ..nextPayload = const GoogleSignInPayload(idToken: 'fake-id-token');
        final profileRepository = _RecordingUserProfileRepository();
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: profileRepository,
          googleSignInService: googleSignIn,
        );

        await repository.signInWithGoogle();

        final profile = await profileRepository.getProfile('google-uid-noname');
        expect(profile!.displayName, isNotEmpty);
      },
    );

    test(
      'returning Google user: an existing profile is never touched or overwritten',
      () async {
        final mockAuth = MockFirebaseAuth(
          mockUser: await _googleMockUser(
            uid: 'google-uid-returning',
            email: 'returning@example.com',
            displayName: 'Latest Google Name',
          ),
        );
        final googleSignIn = FakeGoogleSignInService()
          ..nextPayload = const GoogleSignInPayload(idToken: 'fake-id-token');
        final profileRepository = _RecordingUserProfileRepository();
        // The customer already customized their profile after first sign-in.
        await profileRepository.createProfile(
          uid: 'google-uid-returning',
          email: 'returning@example.com',
          displayName: 'My Customized Name',
          phone: '03001234567',
        );
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: profileRepository,
          googleSignInService: googleSignIn,
        );

        final result = await repository.signInWithGoogle();

        expect(result.success, isTrue);
        final profile = await profileRepository.getProfile(
          'google-uid-returning',
        );
        expect(
          profile!.displayName,
          'My Customized Name',
          reason:
              'the stored profile must never be overwritten by the '
              'Google account\'s current display name',
        );
        expect(profile.phone, '03001234567');
      },
    );

    test(
      'the user cancelling the account picker is reported as cancelled, not a failure',
      () async {
        final mockAuth = MockFirebaseAuth();
        final googleSignIn = FakeGoogleSignInService(); // nextPayload left null
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: MockUserProfileRepository(),
          googleSignInService: googleSignIn,
        );

        final result = await repository.signInWithGoogle();

        expect(result.success, isFalse);
        expect(result.cancelled, isTrue);
        expect(result.errorMessage, isNull);
        expect(mockAuth.currentUser, isNull);
      },
    );

    test(
      'a configuration failure from the sign-in service surfaces its message',
      () async {
        final mockAuth = MockFirebaseAuth();
        final googleSignIn = FakeGoogleSignInService()
          ..nextFailure = const GoogleSignInFailure(
            GoogleSignInFailureReason.configuration,
            'Google Sign-In is not set up correctly yet.',
          );
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: MockUserProfileRepository(),
          googleSignInService: googleSignIn,
        );

        final result = await repository.signInWithGoogle();

        expect(result.success, isFalse);
        expect(result.cancelled, isFalse);
        expect(
          result.errorMessage,
          'Google Sign-In is not set up correctly yet.',
        );
      },
    );

    test(
      'maps account-exists-with-different-credential to a clean, accurate message',
      () async {
        final mockAuth = MockFirebaseAuth();
        whenCalling(Invocation.method(#signInWithCredential, null))
            .on(mockAuth)
            .thenThrow(
              FirebaseAuthException(
                code: 'account-exists-with-different-credential',
              ),
            );
        final googleSignIn = FakeGoogleSignInService()
          ..nextPayload = const GoogleSignInPayload(idToken: 'fake-id-token');
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: MockUserProfileRepository(),
          googleSignInService: googleSignIn,
        );

        final result = await repository.signInWithGoogle();

        expect(result.success, isFalse);
        expect(
          result.errorMessage,
          'An account already exists with this email using a '
          'password. Please sign in with your email and password instead.',
        );
      },
    );

    test(
      'maps user-disabled to the same clean message as email/password',
      () async {
        final mockAuth = MockFirebaseAuth();
        whenCalling(
          Invocation.method(#signInWithCredential, null),
        ).on(mockAuth).thenThrow(FirebaseAuthException(code: 'user-disabled'));
        final googleSignIn = FakeGoogleSignInService()
          ..nextPayload = const GoogleSignInPayload(idToken: 'fake-id-token');
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: MockUserProfileRepository(),
          googleSignInService: googleSignIn,
        );

        final result = await repository.signInWithGoogle();

        expect(
          result.errorMessage,
          'This account has been disabled. Please contact support.',
        );
      },
    );

    test(
      'a profile-write failure does not fail the sign-in (self-heals on next attempt)',
      () async {
        final mockAuth = MockFirebaseAuth(
          mockUser: await _googleMockUser(
            uid: 'google-uid-broken-profile',
            email: 'broken@example.com',
            displayName: 'Broken Profile',
          ),
        );
        final googleSignIn = FakeGoogleSignInService()
          ..nextPayload = const GoogleSignInPayload(idToken: 'fake-id-token');
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: _ThrowingUserProfileRepository(),
          googleSignInService: googleSignIn,
        );

        final result = await repository.signInWithGoogle();

        expect(
          result.success,
          isTrue,
          reason:
              'unlike signUp, this user is already mid-session - a '
              'profile-write hiccup must never strand or sign them out',
        );
        expect(result.userId, 'google-uid-broken-profile');
      },
    );

    test(
      'a profile-write failure self-heals across repeated authStateChanges emissions '
      '(the same mechanism an app restart / persisted-session resume relies on), '
      'and never overwrites once a profile exists',
      () async {
        final flakyRepo = _FlakyThenWorkingUserProfileRepository(
          failCreatesRemaining: 1,
        );
        final mockUser = await _googleMockUser(
          uid: 'google-uid-restart',
          email: 'restart@example.com',
          displayName: 'Restart User',
        );
        final mockAuth = MockFirebaseAuth(mockUser: mockUser);
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: flakyRepo,
          googleSignInService: FakeGoogleSignInService(),
        );

        final emissions = <AuthResult?>[];
        final subscription = repository.authStateChanges().listen(
          emissions.add,
        );
        addTearDown(subscription.cancel);
        // `firebase_auth_mocks` replays one buffered `null` emission (from
        // MockFirebaseAuth's own construction-time notify) to the first
        // listener alongside every real event - filter to successful,
        // non-null results so this test asserts on OUR emissions, not that
        // mock-library quirk.
        List<AuthResult> successes() =>
            emissions.whereType<AuthResult>().where((r) => r.success).toList();

        // Emission #1: the profile write fails (transient) - non-fatal to
        // the emitted session, but no profile exists yet.
        await mockAuth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: 'first'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(successes().length, 1);
        expect(await flakyRepo.getProfile('google-uid-restart'), isNull);

        // Emission #2 (proxy for "the app resolves the persisted session
        // again on next launch"): the same transient failure has cleared -
        // the profile now gets created without anyone calling
        // signInWithGoogle a second time.
        await mockAuth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: 'second'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(successes().length, 2);
        final profile = await flakyRepo.getProfile('google-uid-restart');
        expect(profile, isNotNull);
        expect(profile!.displayName, 'Restart User');
        expect(profile.phone, '');

        // A third emission must NOT create a second time / overwrite.
        await mockAuth.signInWithCredential(
          GoogleAuthProvider.credential(idToken: 'third'),
        );
        await Future<void>.delayed(Duration.zero);
        expect(
          flakyRepo.createProfileCallCount,
          2,
          reason:
              'one failed attempt + one successful attempt - the third '
              'emission must see the now-existing profile and skip',
        );
      },
    );

    test(
      'authStateChanges never reads or writes Firestore for a non-Google (email/password) session',
      () async {
        final countingRepo = _FlakyThenWorkingUserProfileRepository();
        final mockAuth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'pw-uid', email: 'pw@example.com'),
        );
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: countingRepo,
          googleSignInService: FakeGoogleSignInService(),
        );

        final emissions = <AuthResult?>[];
        final subscription = repository.authStateChanges().listen(
          emissions.add,
        );
        addTearDown(subscription.cancel);

        await mockAuth.signInWithEmailAndPassword(
          email: 'pw@example.com',
          password: 'irrelevant',
        );
        await Future<void>.delayed(Duration.zero);

        final successes = emissions
            .whereType<AuthResult>()
            .where((r) => r.success)
            .toList();
        expect(successes.length, 1);
        expect(
          countingRepo.getProfileCallCount,
          0,
          reason:
              'a non-Google session must never trigger the Google-only '
              'profile self-heal check at all',
        );
        expect(countingRepo.createProfileCallCount, 0);
      },
    );

    test(
      'role is resolved only from the ID token claim, never inferred from the Google '
      'account - an admin-sounding email/name with no claim still resolves to customer',
      () async {
        final mockAuth = MockFirebaseAuth(
          mockUser: await _googleMockUser(
            uid: 'google-uid-looks-like-admin',
            email: 'admin@example.com',
            displayName: 'Site Administrator',
          ),
        );
        final googleSignIn = FakeGoogleSignInService()
          ..nextPayload = const GoogleSignInPayload(idToken: 'fake-id-token');
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: MockUserProfileRepository(),
          googleSignInService: googleSignIn,
        );

        final result = await repository.signInWithGoogle();

        expect(
          result.role,
          UserRole.customer,
          reason:
              'no client path ever grants superAdmin from Google '
              'account data - only a real custom claim can',
        );
      },
    );
  });

  group('FirebaseAuthRepository - sendPasswordResetEmail', () {
    test('success returns null', () async {
      final mockAuth = MockFirebaseAuth();
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final error = await repository.sendPasswordResetEmail(
        email: 'test@example.com',
      );

      expect(error, isNull);
    });

    test('maps a thrown error to a clean message', () async {
      final mockAuth = MockFirebaseAuth();
      whenCalling(Invocation.method(#sendPasswordResetEmail, null))
          .on(mockAuth)
          .thenThrow(FirebaseAuthException(code: 'too-many-requests'));
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final error = await repository.sendPasswordResetEmail(
        email: 'test@example.com',
      );

      expect(error, 'Too many attempts. Please try again later.');
    });
  });

  group('FirebaseAuthRepository - signOut', () {
    test('clears the current Firebase user', () async {
      final mockAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'uid-1', email: 'test@example.com'),
      );
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      expect(mockAuth.currentUser, isNotNull);
      await repository.signOut();
      expect(mockAuth.currentUser, isNull);
    });

    test(
      'also best-effort signs out of the on-device Google session',
      () async {
        final mockAuth = MockFirebaseAuth(
          signedIn: true,
          mockUser: MockUser(uid: 'uid-1', email: 'test@example.com'),
        );
        final googleSignIn = FakeGoogleSignInService();
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: MockUserProfileRepository(),
          googleSignInService: googleSignIn,
        );

        await repository.signOut();

        expect(googleSignIn.signOutCalled, isTrue);
      },
    );
  });

  group('FirebaseAuthRepository - authStateChanges', () {
    test(
      'emits a customer-role AuthResult when a user signs in with no claim',
      () async {
        final mockAuth = MockFirebaseAuth(
          mockUser: MockUser(uid: 'uid-1', email: 'test@example.com'),
        );
        final repository = FirebaseAuthRepository(
          firebaseAuth: mockAuth,
          userProfileRepository: MockUserProfileRepository(),
        );

        final results = <dynamic>[];
        final subscription = repository.authStateChanges().listen(results.add);
        addTearDown(subscription.cancel);

        await mockAuth.signInWithEmailAndPassword(
          email: 'test@example.com',
          password: 'Password123!',
        );
        await Future<void>.delayed(Duration.zero);

        expect(results, isNotEmpty);
        expect(results.last.success, isTrue);
        expect(results.last.userId, 'uid-1');
        expect(results.last.role, UserRole.customer);
      },
    );

    test('emits a superAdmin-role AuthResult for a superAdmin claim', () async {
      final mockAuth = MockFirebaseAuth(
        mockUser: MockUser(
          uid: 'uid-admin',
          email: 'admin@example.com',
          customClaim: {'role': 'superAdmin'},
        ),
      );
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final results = <dynamic>[];
      final subscription = repository.authStateChanges().listen(results.add);
      addTearDown(subscription.cancel);

      await mockAuth.signInWithEmailAndPassword(
        email: 'admin@example.com',
        password: 'Password123!',
      );
      await Future<void>.delayed(Duration.zero);

      expect(results.last.role, UserRole.superAdmin);
    });

    test('emits null when signed out', () async {
      final mockAuth = MockFirebaseAuth(
        signedIn: true,
        mockUser: MockUser(uid: 'uid-1', email: 'test@example.com'),
      );
      final repository = FirebaseAuthRepository(
        firebaseAuth: mockAuth,
        userProfileRepository: MockUserProfileRepository(),
      );

      final results = <dynamic>[];
      final subscription = repository.authStateChanges().listen(results.add);
      addTearDown(subscription.cancel);

      await mockAuth.signOut();
      await Future<void>.delayed(Duration.zero);

      expect(results, isNotEmpty);
      expect(results.last, isNull);
    });
  });
}
