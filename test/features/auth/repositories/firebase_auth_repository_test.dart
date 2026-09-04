import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mock_exceptions/mock_exceptions.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/features/auth/repositories/firebase_auth_repository.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/repositories/user_profile_repository.dart';

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
