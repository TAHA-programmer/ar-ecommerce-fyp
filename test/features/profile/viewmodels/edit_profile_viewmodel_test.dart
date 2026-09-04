import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/customer_profile_state.dart';
import 'package:twin_ar/core/models/auth/user_profile_model.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/profile/repositories/mock_user_profile_repository.dart';
import 'package:twin_ar/features/profile/viewmodels/edit_profile_viewmodel.dart';
import '../../../support/test_image_files.dart';

const _uid = 'uid-1';

void main() {
  group('EditProfileViewModel Tests', () {
    late MockUserProfileRepository repository;
    late CustomerProfileState profileState;
    late EditProfileViewModel viewModel;

    setUp(() async {
      repository = MockUserProfileRepository(
        seed: {
          _uid: const UserProfileModel(
            uid: _uid,
            email: 'jane@example.com',
            displayName: 'Jane Doe',
            phone: '03001234567',
            role: 'customer',
          ),
        },
      );
      profileState = CustomerProfileState(
        repository,
        storageService: MockStorageService(),
      );
      await profileState.loadForUser(_uid);
      viewModel = EditProfileViewModel(profileState);
    });

    tearDown(() async {
      await TestImageFile.cleanUp();
    });

    test('initializes with values from profileState', () {
      expect(viewModel.draftFullName, profileState.fullName);
      expect(viewModel.email, profileState.email);
      expect(viewModel.draftPhoneNumber, profileState.phoneNumber);
      expect(viewModel.avatarBytes, profileState.avatarBytes);
    });

    test(
      'there is no way to change the draft email - no updateEmail method exists',
      () {
        // Compile-time guarantee: EditProfileViewModel exposes `email` as a
        // final field, not a mutable draft, and has no updateEmail method.
        // This test documents that intent for anyone reading the test suite.
        expect(viewModel.email, 'jane@example.com');
      },
    );

    test('updateName changes draft value and clears error', () {
      viewModel.updateName('');
      viewModel.saveChanges(); // trigger validation
      expect(viewModel.nameError, isNotNull);

      viewModel.updateName('New Name');
      expect(viewModel.draftFullName, 'New Name');
      expect(viewModel.nameError, isNull);
    });

    test('validation fails for empty fields', () async {
      viewModel.updateName('');
      viewModel.updatePhone('');

      final result = await viewModel.saveChanges();
      expect(result, isFalse);
      expect(viewModel.nameError, isNotNull);
      expect(viewModel.phoneError, isNotNull);
    });

    // Phase 8.12: the approved display-name validation (1-100 chars) is
    // unchanged.
    test('validation fails for a name longer than 100 characters', () async {
      viewModel.updateName('a' * 101);
      viewModel.updatePhone('03001234567');

      final result = await viewModel.saveChanges();
      expect(result, isFalse);
      expect(viewModel.nameError, contains('100'));
    });

    // Phase 8.12: the phone must be a standard Pakistani local mobile
    // number (^03[0-9]{9}$) - the client validator matches the
    // `users/{uid}.phone` Firestore rule exactly.
    group('phone (Pakistani local mobile 03XXXXXXXXX)', () {
      Future<bool> saveWithPhone(String phone) {
        viewModel.updateName('Jane Doe');
        viewModel.updatePhone(phone);
        return viewModel.saveChanges();
      }

      test('a valid 03XXXXXXXXX number saves cleanly', () async {
        expect(await saveWithPhone('03009998888'), isTrue);
        expect(viewModel.phoneError, isNull);
        expect(profileState.phoneNumber, '03009998888');
      });

      test('fewer than 11 digits is rejected with a clean message', () async {
        expect(await saveWithPhone('0300999888'), isFalse);
        expect(
          viewModel.phoneError,
          'Enter an 11-digit mobile number starting with 03.',
        );
      });

      test('more than 11 digits is rejected', () async {
        expect(await saveWithPhone('030099988877'), isFalse);
        expect(viewModel.phoneError, isNotNull);
      });

      test('a wrong prefix is rejected', () async {
        expect(await saveWithPhone('04009998888'), isFalse);
        expect(viewModel.phoneError, isNotNull);
      });

      test('the +92 format is rejected', () async {
        expect(await saveWithPhone('+923009998888'), isFalse);
        expect(viewModel.phoneError, isNotNull);
      });

      test('spaces and hyphens are rejected', () async {
        expect(await saveWithPhone('0300 999 8888'), isFalse);
        expect(await saveWithPhone('0300-999-8888'), isFalse);
      });

      test('letters are rejected', () async {
        expect(await saveWithPhone('0300abcdefg'), isFalse);
        expect(viewModel.phoneError, isNotNull);
      });

      test('an empty value is rejected', () async {
        expect(await saveWithPhone(''), isFalse);
        expect(viewModel.phoneError, isNotNull);
      });
    });

    test('a 100-char name with a valid phone saves cleanly', () async {
      viewModel.updateName('a' * 100);
      viewModel.updatePhone('03001234567');

      final result = await viewModel.saveChanges();
      expect(result, isTrue);
      expect(viewModel.nameError, isNull);
      expect(viewModel.phoneError, isNull);
    });

    test('saveChanges updates profile state if valid', () async {
      viewModel.updateName('Updated Name');
      viewModel.updatePhone('03009998888');

      final result = await viewModel.saveChanges();

      expect(result, isTrue);
      expect(profileState.fullName, 'Updated Name');
      expect(profileState.phoneNumber, '03009998888');
      // Email is never touched by a profile update.
      expect(profileState.email, 'jane@example.com');
    });

    test(
      'avatar upload is independent of phone validation - a legacy-format '
      'draft phone never blocks it (uploadAvatar does not run _validate)',
      () async {
        // Simulate a pre-8.12 profile whose stored phone predates the
        // Pakistani-mobile format.
        final legacyRepo = MockUserProfileRepository(
          seed: {
            _uid: const UserProfileModel(
              uid: _uid,
              email: 'jane@example.com',
              displayName: 'Jane Doe',
              phone: '+1 234-567-8900',
              role: 'customer',
            ),
          },
        );
        final legacyState = CustomerProfileState(
          legacyRepo,
          storageService: MockStorageService(),
        );
        await legacyState.loadForUser(_uid);
        final legacyViewModel = EditProfileViewModel(legacyState);
        expect(legacyViewModel.draftPhoneNumber, '+1 234-567-8900');

        final file = await TestImageFile.create();
        await legacyViewModel.uploadAvatar(file);

        expect(legacyViewModel.avatarError, isNull);
        expect(legacyState.avatarStoragePath, isNotNull);
      },
    );

    test(
      'uploadAvatar delegates to profileState and is independent of saveChanges',
      () async {
        final file = await TestImageFile.create();

        await viewModel.uploadAvatar(file);

        expect(viewModel.avatarError, isNull);
        expect(viewModel.isAvatarUploading, isFalse);
        expect(profileState.avatarStoragePath, isNotNull);
        expect(viewModel.avatarBytes, profileState.avatarBytes);
      },
    );

    test('uploadAvatar surfaces a clean avatarError on failure', () async {
      final failingStorage = MockStorageService()
        ..failUploadAvatarWith = Exception('boom');
      final failingProfileState = CustomerProfileState(
        repository,
        storageService: failingStorage,
      );
      await failingProfileState.loadForUser(_uid);
      final failingViewModel = EditProfileViewModel(failingProfileState);
      final file = await TestImageFile.create();

      await failingViewModel.uploadAvatar(file);

      expect(failingViewModel.avatarError, isNotNull);
      expect(failingViewModel.isAvatarUploading, isFalse);
    });

    test(
      'uploadAvatar surfaces a clean preflight avatarError for an oversized file, without ever calling Storage',
      () async {
        final storage = MockStorageService();
        final localState = CustomerProfileState(
          repository,
          storageService: storage,
        );
        await localState.loadForUser(_uid);
        final localViewModel = EditProfileViewModel(localState);
        final oversized = await TestImageFile.create(
          sizeBytes: 3 * 1024 * 1024,
        );

        await localViewModel.uploadAvatar(oversized);

        expect(localViewModel.avatarError, isNotNull);
        expect(localViewModel.avatarError, contains('too large'));
        expect(storage.uploadedAvatarPaths, isEmpty);
      },
    );

    test(
      'saveChanges surfaces a saveError when the repository fails',
      () async {
        // No signed-in user loaded on this profileState/repository pairing -
        // updateProfile() fails safely per CustomerProfileState's own test
        // coverage, and that failure must reach the ViewModel as saveError.
        final unloadedState = CustomerProfileState(MockUserProfileRepository());
        final unloadedViewModel = EditProfileViewModel(unloadedState);
        unloadedViewModel.updateName('Someone');
        unloadedViewModel.updatePhone('03001112223');

        final result = await unloadedViewModel.saveChanges();

        expect(result, isFalse);
        expect(unloadedViewModel.saveError, isNotNull);
      },
    );
  });
}
