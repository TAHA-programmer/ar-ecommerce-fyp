import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/profile/repositories/firestore_user_profile_repository.dart';

void main() {
  group('FirestoreUserProfileRepository', () {
    test('createProfile writes the expected document shape', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirestoreUserProfileRepository(firestore: firestore);

      await repository.createProfile(
        uid: 'uid-1',
        email: 'jane@example.com',
        displayName: 'Jane Doe',
        phone: '1234567890',
      );

      final doc = await firestore.collection('users').doc('uid-1').get();
      final data = doc.data()!;
      expect(data['uid'], 'uid-1');
      expect(data['email'], 'jane@example.com');
      expect(data['displayName'], 'Jane Doe');
      expect(data['phone'], '1234567890');
      // A brand-new profile is always 'customer' - there is no code path
      // in this repository that can write anything else.
      expect(data['role'], 'customer');
      expect(data['createdAt'], isA<Timestamp>());
    });

    test('getProfile maps a document back to a UserProfileModel', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirestoreUserProfileRepository(firestore: firestore);
      await repository.createProfile(
        uid: 'uid-1',
        email: 'jane@example.com',
        displayName: 'Jane Doe',
        phone: '1234567890',
      );

      final profile = await repository.getProfile('uid-1');

      expect(profile, isNotNull);
      expect(profile!.uid, 'uid-1');
      expect(profile.email, 'jane@example.com');
      expect(profile.displayName, 'Jane Doe');
      expect(profile.phone, '1234567890');
      expect(profile.role, 'customer');
      expect(profile.createdAt, isNotNull);
    });

    test('getProfile returns null for a non-existent uid', () async {
      final firestore = FakeFirebaseFirestore();
      final repository = FirestoreUserProfileRepository(firestore: firestore);

      final profile = await repository.getProfile('does-not-exist');

      expect(profile, isNull);
    });

    test(
      'updateProfile only touches displayName/phone, never role/email/uid/createdAt',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = FirestoreUserProfileRepository(firestore: firestore);
        await repository.createProfile(
          uid: 'uid-1',
          email: 'jane@example.com',
          displayName: 'Jane Doe',
          phone: '1234567890',
        );

        await repository.updateProfile(
          uid: 'uid-1',
          displayName: 'Updated Name',
          phone: '9999999999',
        );

        final doc = await firestore.collection('users').doc('uid-1').get();
        final data = doc.data()!;
        expect(data['displayName'], 'Updated Name');
        expect(data['phone'], '9999999999');
        expect(data['role'], 'customer');
        expect(data['email'], 'jane@example.com');
        expect(data['uid'], 'uid-1');
      },
    );

    test(
      'updateAvatarStoragePath only touches avatarStoragePath (Phase 8.7)',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = FirestoreUserProfileRepository(firestore: firestore);
        await repository.createProfile(
          uid: 'uid-1',
          email: 'jane@example.com',
          displayName: 'Jane Doe',
          phone: '1234567890',
        );

        await repository.updateAvatarStoragePath(
          uid: 'uid-1',
          avatarStoragePath: 'users/uid-1/profile/abc.jpg',
        );

        final doc = await firestore.collection('users').doc('uid-1').get();
        final data = doc.data()!;
        expect(data['avatarStoragePath'], 'users/uid-1/profile/abc.jpg');
        expect(data['displayName'], 'Jane Doe');
        expect(data['phone'], '1234567890');
        expect(data['role'], 'customer');

        final profile = await repository.getProfile('uid-1');
        expect(profile!.avatarStoragePath, 'users/uid-1/profile/abc.jpg');
      },
    );

    test(
      'updateAvatarStoragePath(null) clears a previously set avatar',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = FirestoreUserProfileRepository(firestore: firestore);
        await repository.createProfile(
          uid: 'uid-1',
          email: 'jane@example.com',
          displayName: 'Jane Doe',
          phone: '1234567890',
        );
        await repository.updateAvatarStoragePath(
          uid: 'uid-1',
          avatarStoragePath: 'users/uid-1/profile/abc.jpg',
        );

        await repository.updateAvatarStoragePath(
          uid: 'uid-1',
          avatarStoragePath: null,
        );

        final profile = await repository.getProfile('uid-1');
        expect(profile!.avatarStoragePath, isNull);
      },
    );

    test(
      'getProfile returns a null avatarStoragePath for a profile that never uploaded one',
      () async {
        final firestore = FakeFirebaseFirestore();
        final repository = FirestoreUserProfileRepository(firestore: firestore);
        await repository.createProfile(
          uid: 'uid-1',
          email: 'jane@example.com',
          displayName: 'Jane Doe',
          phone: '1234567890',
        );

        final profile = await repository.getProfile('uid-1');

        expect(profile!.avatarStoragePath, isNull);
      },
    );
  });
}
