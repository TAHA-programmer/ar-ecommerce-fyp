import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/core/services/storage_service.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/repositories/user_profile_repository.dart';
import '../../../support/test_image_files.dart';

const _uid = 'uid-1';
const _otherUid = 'uid-2';

/// Wraps [MockUserProfileRepository] and makes ONLY
/// [updateAvatarStoragePath] throw - used to exercise
/// `CustomerProfileState.uploadAvatar`'s rollback path (Storage upload
/// succeeds, the following Firestore commit fails).
class _ThrowingAvatarCommitRepository implements UserProfileRepository {
  final MockUserProfileRepository _delegate;
  _ThrowingAvatarCommitRepository(this._delegate);

  @override
  Future<void> createProfile({
    required String uid,
    required String email,
    required String displayName,
    required String phone,
  }) => _delegate.createProfile(
    uid: uid,
    email: email,
    displayName: displayName,
    phone: phone,
  );

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
  }) async {
    throw Exception('simulated Firestore failure');
  }
}

/// Test-only [UserProfileRepository] double whose [getProfile] result is
/// controlled explicitly per-uid via a [Completer], so a test can start
/// `loadForUser` for two different users and decide the exact order in
/// which each one's fetch resolves - the only way to deterministically
/// reproduce "User A's fetch finishes after User B has already started
/// loading" instead of hoping for a timing accident.
class _ControllableUserProfileRepository implements UserProfileRepository {
  final Map<String, Completer<UserProfileModel?>> _getProfileCompleters = {};

  Completer<UserProfileModel?> completerFor(String uid) => _getProfileCompleters
      .putIfAbsent(uid, () => Completer<UserProfileModel?>());

  @override
  Future<UserProfileModel?> getProfile(String uid) => completerFor(uid).future;

  @override
  Future<void> createProfile({
    required String uid,
    required String email,
    required String displayName,
    required String phone,
  }) async {}

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

/// Test-only [StorageService] double giving explicit, per-operation control
/// over when an avatar download/upload resolves - the other half of
/// reproducing the race conditions [_ControllableUserProfileRepository]
/// covers for profile fetches. `downloadAvatarBytes` resolves immediately
/// unless the caller opts a specific path into gating via [gateDownload]
/// (so unrelated loads in the same test don't also need wiring). Product-
/// image methods are unused by any test using this double and throw if
/// ever called, to fail loudly rather than silently no-op.
class _ControllableStorageService implements StorageService {
  final Map<String, Completer<Uint8List>> _downloadCompleters = {};
  final Map<String, Completer<String>> _uploadAvatarCompleters = {};
  final Set<String> _gatedDownloadPaths = {};
  final List<String> uploadedAvatarPaths = [];
  final List<String> deletedAvatarPaths = [];

  void gateDownload(String path) => _gatedDownloadPaths.add(path);

  Completer<Uint8List> downloadCompleterFor(String path) =>
      _downloadCompleters.putIfAbsent(path, () => Completer<Uint8List>());

  Completer<String> uploadCompleterFor(String uid) =>
      _uploadAvatarCompleters.putIfAbsent(uid, () => Completer<String>());

  @override
  Future<Uint8List> downloadAvatarBytes(
    String storagePath, {
    int maxSize = 2 * 1024 * 1024,
  }) {
    if (_gatedDownloadPaths.contains(storagePath)) {
      return downloadCompleterFor(storagePath).future;
    }
    return Future.value(Uint8List.fromList([1, 2, 3]));
  }

  @override
  Future<String> uploadAvatar({
    required String uid,
    required String objectName,
    required File file,
  }) async {
    final path = await uploadCompleterFor(uid).future;
    uploadedAvatarPaths.add(path);
    return path;
  }

  @override
  Future<void> deleteAvatarByPath(String storagePath) async {
    deletedAvatarPaths.add(storagePath);
  }

  @override
  Future<String> uploadProductImage({
    required String productId,
    required String objectName,
    required File file,
  }) => throw UnimplementedError('not used by these tests');

  @override
  Future<void> deleteProductImageByUrl(String downloadUrl) =>
      throw UnimplementedError('not used by these tests');

  @override
  Future<String> uploadCategoryImage({
    required String categoryId,
    required String objectName,
    required File file,
  }) => throw UnimplementedError('not used by these tests');

  @override
  Future<void> deleteCategoryImageByUrl(String downloadUrl) =>
      throw UnimplementedError('not used by these tests');

  @override
  Future<String> uploadArModel({
    required String productId,
    required String objectName,
    required File file,
    Map<String, String>? provenance,
    void Function(double progress)? onProgress,
  }) => throw UnimplementedError('not used by these tests');

  @override
  Future<Uint8List> downloadArModelBytes(
    String storagePath, {
    int maxSize = 16 * 1024 * 1024,
  }) => throw UnimplementedError('not used by these tests');

  @override
  Future<bool> deleteArModelByPath(String storagePath) =>
      throw UnimplementedError('not used by these tests');
}

UserProfileModel _seedProfile({
  String uid = _uid,
  String displayName = 'Jane Doe',
  String phone = '1234567890',
  String? avatarStoragePath,
}) => UserProfileModel(
  uid: uid,
  email: '$uid@example.com',
  displayName: displayName,
  phone: phone,
  role: 'customer',
  avatarStoragePath: avatarStoragePath,
);

void main() {
  tearDown(() async {
    await TestImageFile.cleanUp();
  });

  group('CustomerProfileState Tests', () {
    test('initial values are empty before any user is loaded', () {
      final state = CustomerProfileState(MockUserProfileRepository());

      expect(state.fullName, '');
      expect(state.email, '');
      expect(state.phoneNumber, '');
      expect(state.avatarStoragePath, isNull);
      expect(state.avatarBytes, isNull);
      expect(state.isAvatarLoading, isFalse);
    });

    test('loadForUser populates fields from the repository', () async {
      final repository = MockUserProfileRepository(
        seed: {_uid: _seedProfile()},
      );
      final state = CustomerProfileState(repository);

      await state.loadForUser(_uid);

      expect(state.fullName, 'Jane Doe');
      expect(state.email, '$_uid@example.com');
      expect(state.phoneNumber, '1234567890');
    });

    test(
      'loadForUser with an existing avatarStoragePath fetches and caches the avatar bytes',
      () async {
        final repository = MockUserProfileRepository(
          seed: {
            _uid: _seedProfile(avatarStoragePath: 'users/$_uid/profile/a.jpg'),
          },
        );
        final storage = MockStorageService();
        final state = CustomerProfileState(repository, storageService: storage);

        await state.loadForUser(_uid);

        expect(state.avatarStoragePath, 'users/$_uid/profile/a.jpg');
        expect(state.avatarBytes, isNotNull);
        expect(state.isAvatarLoading, isFalse);
      },
    );

    test(
      'loadForUser with no avatarStoragePath never touches storage',
      () async {
        final repository = MockUserProfileRepository(
          seed: {_uid: _seedProfile()},
        );
        final storage = MockStorageService();
        final state = CustomerProfileState(repository, storageService: storage);

        await state.loadForUser(_uid);

        expect(state.avatarStoragePath, isNull);
        expect(state.avatarBytes, isNull);
      },
    );

    test(
      'a failed avatar bytes fetch degrades silently to no-avatar rather than throwing',
      () async {
        final repository = MockUserProfileRepository(
          seed: {
            _uid: _seedProfile(avatarStoragePath: 'users/$_uid/profile/a.jpg'),
          },
        );
        final storage = MockStorageService()
          ..failDownloadAvatarWith = const StorageServiceException(
            'network error',
          );
        final state = CustomerProfileState(repository, storageService: storage);

        await state.loadForUser(_uid);

        expect(state.avatarBytes, isNull);
        expect(state.isAvatarLoading, isFalse);
      },
    );

    test('loadForUser(null) clears a previously loaded profile', () async {
      final repository = MockUserProfileRepository(
        seed: {_uid: _seedProfile()},
      );
      final state = CustomerProfileState(repository);
      await state.loadForUser(_uid);
      expect(state.fullName, 'Jane Doe');

      await state.loadForUser(null);

      expect(state.fullName, '');
      expect(state.email, '');
      expect(state.phoneNumber, '');
      expect(state.avatarStoragePath, isNull);
      expect(state.avatarBytes, isNull);
    });

    test(
      'switching from one signed-in user to another never leaks the first user avatar - cross-user isolation (sequential)',
      () async {
        final repository = MockUserProfileRepository(
          seed: {
            _uid: _seedProfile(
              displayName: 'User One',
              avatarStoragePath: 'users/$_uid/profile/a.jpg',
            ),
            _otherUid: _seedProfile(uid: _otherUid, displayName: 'User Two'),
          },
        );
        final storage = MockStorageService();
        final state = CustomerProfileState(repository, storageService: storage);

        await state.loadForUser(_uid);
        expect(state.avatarStoragePath, 'users/$_uid/profile/a.jpg');
        expect(state.avatarBytes, isNotNull);

        // Simulate logout -> login as a different user, exactly as
        // app_providers.dart's ChangeNotifierProxyProvider3 drives this in
        // production (loadForUser(null) on logout, loadForUser(newUid) on
        // the next login).
        await state.loadForUser(null);
        await state.loadForUser(_otherUid);

        expect(state.fullName, 'User Two');
        expect(state.avatarStoragePath, isNull);
        expect(state.avatarBytes, isNull);
      },
    );

    test(
      'loadForUser is a no-op when called again with the same uid',
      () async {
        final repository = MockUserProfileRepository(
          seed: {_uid: _seedProfile()},
        );
        final state = CustomerProfileState(repository);
        await state.loadForUser(_uid);

        // Mutate the repository directly to prove a second loadForUser(_uid)
        // does not refetch - it should keep the first-loaded value.
        await repository.updateProfile(
          uid: _uid,
          displayName: 'Changed Elsewhere',
          phone: '0000000000',
        );
        await state.loadForUser(_uid);

        expect(state.fullName, 'Jane Doe');
      },
    );

    test(
      'updateProfile writes through the repository and updates locally',
      () async {
        final repository = MockUserProfileRepository(
          seed: {_uid: _seedProfile()},
        );
        final state = CustomerProfileState(repository);
        await state.loadForUser(_uid);
        bool listenerCalled = false;
        state.addListener(() => listenerCalled = true);

        final error = await state.updateProfile(
          name: 'Updated Name',
          phone: '9999999999',
        );

        expect(error, isNull);
        expect(state.fullName, 'Updated Name');
        expect(state.phoneNumber, '9999999999');
        expect(listenerCalled, isTrue);

        final persisted = await repository.getProfile(_uid);
        expect(persisted?.displayName, 'Updated Name');
        expect(persisted?.phone, '9999999999');
      },
    );

    test('updateProfile fails safely when no user is loaded', () async {
      final state = CustomerProfileState(MockUserProfileRepository());

      final error = await state.updateProfile(name: 'X', phone: 'Y');

      expect(error, isNotNull);
    });

    group('uploadAvatar', () {
      test(
        'uploads to storage, commits the path to the repository, and caches bytes',
        () async {
          final repository = MockUserProfileRepository(
            seed: {_uid: _seedProfile()},
          );
          final storage = MockStorageService();
          final state = CustomerProfileState(
            repository,
            storageService: storage,
          );
          await state.loadForUser(_uid);
          bool listenerCalled = false;
          state.addListener(() => listenerCalled = true);
          final file = await TestImageFile.create();

          final error = await state.uploadAvatar(file);

          expect(error, isNull);
          expect(listenerCalled, isTrue);
          expect(state.avatarStoragePath, isNotNull);
          expect(state.avatarStoragePath, startsWith('users/$_uid/profile/'));
          expect(state.avatarBytes, isNotNull);
          expect(storage.uploadedAvatarPaths, hasLength(1));

          final persisted = await repository.getProfile(_uid);
          expect(persisted?.avatarStoragePath, state.avatarStoragePath);
        },
      );

      test('fails safely when no user is loaded', () async {
        final state = CustomerProfileState(
          MockUserProfileRepository(),
          storageService: MockStorageService(),
        );
        final file = await TestImageFile.create();

        final error = await state.uploadAvatar(file);

        expect(error, isNotNull);
      });

      test(
        'a Storage upload failure never reaches the repository and reports a clean error',
        () async {
          final repository = MockUserProfileRepository(
            seed: {_uid: _seedProfile()},
          );
          final storage = MockStorageService()
            ..failUploadAvatarWith = const StorageServiceException(
              'network error',
            );
          final state = CustomerProfileState(
            repository,
            storageService: storage,
          );
          await state.loadForUser(_uid);
          final file = await TestImageFile.create();

          final error = await state.uploadAvatar(file);

          expect(error, 'network error');
          expect(state.avatarStoragePath, isNull);
          // Upload itself never produced a path, so there is nothing to
          // roll back in this specific case.
          expect(storage.deletedAvatarPaths, isEmpty);
        },
      );

      test(
        'rolls back the just-uploaded object when the Firestore commit fails, and reports an error',
        () async {
          final mock = MockUserProfileRepository(seed: {_uid: _seedProfile()});
          final repository = _ThrowingAvatarCommitRepository(mock);
          final storage = MockStorageService();
          final state = CustomerProfileState(
            repository,
            storageService: storage,
          );
          await state.loadForUser(_uid);
          final file = await TestImageFile.create();

          final error = await state.uploadAvatar(file);

          expect(error, isNotNull);
          expect(state.avatarStoragePath, isNull);
          // The upload DID succeed before the Firestore commit threw - the
          // orphaned object must be rolled back, not left dangling.
          expect(storage.uploadedAvatarPaths, hasLength(1));
          expect(storage.deletedAvatarPaths, storage.uploadedAvatarPaths);
        },
      );

      test(
        'deletes the previous avatar object after a successful re-upload',
        () async {
          final repository = MockUserProfileRepository(
            seed: {
              _uid: _seedProfile(
                avatarStoragePath: 'users/$_uid/profile/old.jpg',
              ),
            },
          );
          final storage = MockStorageService();
          final state = CustomerProfileState(
            repository,
            storageService: storage,
          );
          await state.loadForUser(_uid);
          final file = await TestImageFile.create();

          await state.uploadAvatar(file);

          expect(storage.deletedAvatarPaths, ['users/$_uid/profile/old.jpg']);
        },
      );
    });

    group('uploadAvatar preflight validation', () {
      test(
        'rejects an oversized avatar file before ever calling Storage',
        () async {
          final repository = MockUserProfileRepository(
            seed: {_uid: _seedProfile()},
          );
          final storage = MockStorageService();
          final state = CustomerProfileState(
            repository,
            storageService: storage,
          );
          await state.loadForUser(_uid);
          final oversized = await TestImageFile.create(
            sizeBytes: 3 * 1024 * 1024,
          );

          final error = await state.uploadAvatar(oversized);

          expect(error, isNotNull);
          expect(error, contains('too large'));
          expect(storage.uploadedAvatarPaths, isEmpty);
        },
      );

      test(
        'rejects an unsupported file type before ever calling Storage',
        () async {
          final repository = MockUserProfileRepository(
            seed: {_uid: _seedProfile()},
          );
          final storage = MockStorageService();
          final state = CustomerProfileState(
            repository,
            storageService: storage,
          );
          await state.loadForUser(_uid);
          final unsupported = await TestImageFile.create(extension: 'gif');

          final error = await state.uploadAvatar(unsupported);

          expect(error, isNotNull);
          expect(error, contains('Unsupported'));
          expect(storage.uploadedAvatarPaths, isEmpty);
        },
      );

      test('rejects a missing file before ever calling Storage', () async {
        final repository = MockUserProfileRepository(
          seed: {_uid: _seedProfile()},
        );
        final storage = MockStorageService();
        final state = CustomerProfileState(repository, storageService: storage);
        await state.loadForUser(_uid);
        final missing = File(
          '${Directory.systemTemp.path}/does-not-exist-twin-ar-test.jpg',
        );

        final error = await state.uploadAvatar(missing);

        expect(error, isNotNull);
        expect(storage.uploadedAvatarPaths, isEmpty);
      });
    });

    group('async account isolation - concurrent operations (Completer-based)', () {
      test(
        "User A's profile fetch finishing after User B starts loading never overwrites User B's fields",
        () async {
          final repo = _ControllableUserProfileRepository();
          final storage = MockStorageService();
          final state = CustomerProfileState(repo, storageService: storage);

          final loadA = state.loadForUser('A');
          final loadB = state.loadForUser('B');

          // Resolve A's fetch AFTER B has already started loading.
          repo
              .completerFor('A')
              .complete(
                const UserProfileModel(
                  uid: 'A',
                  email: 'a@x.com',
                  displayName: 'Alice',
                  phone: '1',
                  role: 'customer',
                ),
              );
          await loadA;

          // A's data must NOT have been applied - B is now the active
          // generation, and A's completion must be a silent no-op.
          expect(state.fullName, isNot('Alice'));

          repo
              .completerFor('B')
              .complete(
                const UserProfileModel(
                  uid: 'B',
                  email: 'b@x.com',
                  displayName: 'Bob',
                  phone: '2',
                  role: 'customer',
                ),
              );
          await loadB;

          expect(state.fullName, 'Bob');
          expect(state.email, 'b@x.com');
          expect(state.isLoading, isFalse);
        },
      );

      test(
        "User A's avatar download finishing after logout/User B login never overwrites the new session's avatar",
        () async {
          final repo = _ControllableUserProfileRepository();
          final storage = _ControllableStorageService();
          final state = CustomerProfileState(repo, storageService: storage);
          storage.gateDownload('users/A/profile/a.jpg');

          // User A logs in; the profile resolves promptly, but the avatar
          // bytes fetch is gated and stays pending.
          final loadA = state.loadForUser('A');
          repo
              .completerFor('A')
              .complete(
                const UserProfileModel(
                  uid: 'A',
                  email: 'a@x.com',
                  displayName: 'Alice',
                  phone: '1',
                  role: 'customer',
                  avatarStoragePath: 'users/A/profile/a.jpg',
                ),
              );
          // Let A's continuation run up to (and suspend at) the gated
          // avatar-bytes await - a macrotask boundary drains every pending
          // microtask first, regardless of how many internal awaits chain
          // together.
          await Future.delayed(Duration.zero);
          expect(state.isAvatarLoading, isTrue);

          // Logout - must invalidate A's in-flight avatar fetch and clear
          // both loading flags.
          await state.loadForUser(null);
          expect(state.isLoading, isFalse);
          expect(state.isAvatarLoading, isFalse);
          expect(state.avatarBytes, isNull);

          // User B logs in with no avatar of their own.
          final loadB = state.loadForUser('B');
          repo
              .completerFor('B')
              .complete(
                const UserProfileModel(
                  uid: 'B',
                  email: 'b@x.com',
                  displayName: 'Bob',
                  phone: '2',
                  role: 'customer',
                ),
              );
          await loadB;
          expect(state.fullName, 'Bob');
          expect(state.avatarBytes, isNull);

          // NOW A's stale avatar-bytes fetch resolves.
          storage
              .downloadCompleterFor('users/A/profile/a.jpg')
              .complete(Uint8List.fromList([9, 9, 9]));
          await loadA;

          // B's session must be completely unaffected by A's late-arriving
          // bytes - the core "no stale operation overwrites User B" case.
          expect(state.fullName, 'Bob');
          expect(state.avatarBytes, isNull);
          expect(state.isAvatarLoading, isFalse);
        },
      );

      test(
        "a stale avatar upload finishing after the active uid changes never overwrites or deletes User B's avatar - only User A's own previous avatar is cleaned up",
        () async {
          final repo = MockUserProfileRepository(
            seed: {
              'A': const UserProfileModel(
                uid: 'A',
                email: 'a@x.com',
                displayName: 'Alice',
                phone: '1',
                role: 'customer',
                avatarStoragePath: 'users/A/profile/old.jpg',
              ),
              'B': const UserProfileModel(
                uid: 'B',
                email: 'b@x.com',
                displayName: 'Bob',
                phone: '2',
                role: 'customer',
                avatarStoragePath: 'users/B/profile/existing.jpg',
              ),
            },
          );
          final storage = _ControllableStorageService();
          final state = CustomerProfileState(repo, storageService: storage);

          await state.loadForUser('A');
          expect(state.avatarStoragePath, 'users/A/profile/old.jpg');

          // A starts uploading a new avatar - the upload call is held
          // pending.
          final file = await TestImageFile.create();
          final uploadFuture = state.uploadAvatar(file);

          // Before A's upload resolves, the session switches to B.
          await state.loadForUser(null);
          await state.loadForUser('B');
          expect(state.avatarStoragePath, 'users/B/profile/existing.jpg');

          // NOW A's stale upload resolves.
          storage
              .uploadCompleterFor('A')
              .complete('users/A/profile/new-for-a.jpg');
          final result = await uploadFuture;

          expect(result, isNull);
          // B's session must be completely untouched by A's stale upload.
          expect(state.avatarStoragePath, 'users/B/profile/existing.jpg');
          // A's OWN previous avatar (captured before the switch, so it can
          // never be confused with whatever is current by the time the
          // upload finishes) must still be cleaned up.
          expect(
            storage.deletedAvatarPaths,
            contains('users/A/profile/old.jpg'),
          );
          // B's avatar must NEVER be deleted by A's stale operation.
          expect(
            storage.deletedAvatarPaths,
            isNot(contains('users/B/profile/existing.jpg')),
          );
        },
      );
    });
  });
}
