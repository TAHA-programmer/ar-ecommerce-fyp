import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/firestore_address_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/address/models/address_model.dart';

/// Waits until [notifier] has gone quiet (at least one notify has occurred,
/// and no further notify arrives for [quietPeriod]) - robust for a class
/// backed by more than one independent async subscription (addresses +
/// default pointer here), mirroring
/// `firestore_commerce_database_test.dart`'s established helper.
Future<void> _waitForNotify(
  ChangeNotifier notifier,
  Future<void> Function() act, {
  Duration quietPeriod = const Duration(milliseconds: 60),
  Duration timeout = const Duration(seconds: 5),
}) async {
  DateTime? lastNotify;
  void listener() => lastNotify = DateTime.now();

  notifier.addListener(listener);
  await act();

  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final last = lastNotify;
    if (last != null && DateTime.now().difference(last) > quietPeriod) break;
    await Future.delayed(const Duration(milliseconds: 15));
  }
  notifier.removeListener(listener);
}

AddressDraft _draft({String fullName = 'Test User'}) => AddressDraft(
  fullName: fullName,
  phoneNumber: '1',
  addressLine1: 'L1',
  city: 'C',
  provinceOrState: 'P',
  postalCode: '0',
);

AuthSessionState _sessionFor(String uid) => AuthSessionState()
  ..setSession(
    AuthResult.success(
      userId: uid,
      email: '$uid@x.com',
      role: UserRole.customer,
    ),
  );

void main() {
  group('FirestoreAddressRepository', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('the first address becomes default automatically', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);

      final created = await repo.addAddress(_draft());
      expect(created.isDefault, isTrue);

      await _waitForNotify(repo, () async {});
      expect(repo.addresses.single.isDefault, isTrue);
      expect(repo.addresses.single.id, created.id);
    });

    test('repository-created address IDs are usable immediately and after '
        'reload', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);

      final created = await repo.addAddress(_draft());
      // Immediately usable - a real Firestore document exists at this id.
      final doc = await firestore
          .collection('users')
          .doc('alice')
          .collection('addresses')
          .doc(created.id)
          .get();
      expect(doc.exists, isTrue);

      // Still resolvable after a fresh repository instance "reloads" (a
      // new subscription against the same backing data).
      final reloaded = FirestoreAddressRepository(auth, firestore: firestore);
      await _waitForNotify(reloaded, () async {});
      expect(reloaded.addresses.any((a) => a.id == created.id), isTrue);
    });

    test('a second address does not become default; setDefaultAddress '
        'moves it atomically', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);

      final first = await repo.addAddress(_draft(fullName: 'First'));
      final second = await repo.addAddress(_draft(fullName: 'Second'));
      await _waitForNotify(repo, () async {});
      expect(
        repo.addresses.firstWhere((a) => a.id == second.id).isDefault,
        isFalse,
      );

      await _waitForNotify(repo, () => repo.setDefaultAddress(second.id));
      final byId = {for (final a in repo.addresses) a.id: a.isDefault};
      expect(byId[first.id], isFalse);
      expect(byId[second.id], isTrue);
    });

    test('deleting the default reassigns to the earliest remaining address '
        'by createdAt', () async {
      final auth = _sessionFor('alice');
      final collection = firestore
          .collection('users')
          .doc('alice')
          .collection('addresses');
      // Seed directly with explicit, distinct createdAt values so ordering
      // is deterministic regardless of real wall-clock timing.
      await collection.doc('a1').set({
        'fullName': 'First',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await collection.doc('a2').set({
        'fullName': 'Second',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
      });
      await collection.doc('a3').set({
        'fullName': 'Third',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 3)),
      });
      await firestore
          .collection('users')
          .doc('alice')
          .collection('addressDefault')
          .doc('pointer')
          .set({'defaultAddressId': 'a1'});

      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      await _waitForNotify(repo, () async {});
      expect(repo.defaultAddress?.id, 'a1');

      await _waitForNotify(repo, () => repo.deleteAddress('a1'));

      expect(repo.addresses.map((a) => a.id).toList(), ['a2', 'a3']);
      expect(repo.defaultAddress?.id, 'a2');
    });

    test('deleting the only address leaves no default', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      final only = await repo.addAddress(_draft());
      await _waitForNotify(repo, () async {});

      await _waitForNotify(repo, () => repo.deleteAddress(only.id));
      expect(repo.addresses, isEmpty);
      expect(repo.defaultAddress, isNull);
    });

    test('concurrent setDefaultAddress calls converge to exactly one final '
        'default, never two', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      final first = await repo.addAddress(_draft(fullName: 'First'));
      final second = await repo.addAddress(_draft(fullName: 'Second'));

      await _waitForNotify(repo, () async {
        await Future.wait([
          repo.setDefaultAddress(first.id),
          repo.setDefaultAddress(second.id),
        ]);
      });

      final defaults = repo.addresses.where((a) => a.isDefault).toList();
      expect(defaults.length, 1);
    });

    test('signed-out addAddress fails cleanly and creates no local shared '
        'state', () async {
      final auth = AuthSessionState(); // signed out
      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      await expectLater(repo.addAddress(_draft()), throwsA(isA<StateError>()));
      expect(repo.addresses, isEmpty);
    });

    test('a direct Customer A -> Customer B switch never shows A\'s '
        'addresses to B, even briefly', () async {
      await firestore
          .collection('users')
          .doc('alice')
          .collection('addresses')
          .doc('a1')
          .set({
            'fullName': 'Alice Address',
            'phoneNumber': '1',
            'addressLine1': 'L1',
            'city': 'C',
            'provinceOrState': 'P',
            'postalCode': '0',
            'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          });
      await firestore
          .collection('users')
          .doc('bob')
          .collection('addresses')
          .doc('b1')
          .set({
            'fullName': 'Bob Address',
            'phoneNumber': '1',
            'addressLine1': 'L1',
            'city': 'C',
            'provinceOrState': 'P',
            'postalCode': '0',
            'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          });

      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      await _waitForNotify(repo, () async {});
      expect(repo.addresses.single.fullName, 'Alice Address');

      // Direct switch - same role, different uid, no intervening
      // clearSession().
      await _waitForNotify(repo, () async {
        auth.setSession(
          AuthResult.success(
            userId: 'bob',
            email: 'bob@x.com',
            role: UserRole.customer,
          ),
        );
      });

      expect(repo.addresses.single.fullName, 'Bob Address');
      expect(
        repo.addresses.every((a) => a.fullName != 'Alice Address'),
        isTrue,
      );
    });

    test('a stale-generation snapshot callback (from a since-superseded '
        'subscription) is dropped, never applied', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      await _waitForNotify(repo, () async {});

      final staleGeneration = repo.debugGeneration - 1;
      repo.debugSimulateAddressesSnapshot(staleGeneration, [
        MapEntry('intruder', {
          'fullName': 'Should never appear',
          'phoneNumber': '1',
          'addressLine1': 'L1',
          'city': 'C',
          'provinceOrState': 'P',
          'postalCode': '0',
          'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
        }),
      ]);

      expect(
        repo.addresses.any((a) => a.fullName == 'Should never appear'),
        isFalse,
      );
    });

    test('a transient listener error for the CURRENT uid preserves the '
        'last-good cache instead of clearing to empty', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      await repo.addAddress(_draft());
      await _waitForNotify(repo, () async {});
      expect(repo.addresses, isNotEmpty);
      final beforeError = repo.addresses;

      repo.debugSimulateError(repo.debugGeneration);

      expect(repo.hasError, isTrue);
      expect(repo.addresses.map((a) => a.id), beforeError.map((a) => a.id));
    });

    // --- Pre-deployment correction-pass regression tests ---

    test(
      'addAddress(makeDefault: true) atomically promotes a LATER '
      'address to default in the SAME write as its creation - the '
      'returned model is immediately correct, no listener wait needed',
      () async {
        final auth = _sessionFor('alice');
        final repo = FirestoreAddressRepository(auth, firestore: firestore);

        final first = await repo.addAddress(_draft(fullName: 'First'));
        final second = await repo.addAddress(
          _draft(fullName: 'Second'),
          makeDefault: true,
        );

        // Correct immediately, before any snapshot listener has fired.
        expect(first.isDefault, isTrue); // was true when created (only addr)
        expect(second.isDefault, isTrue);

        await _waitForNotify(repo, () async {});
        final byId = {for (final a in repo.addresses) a.id: a.isDefault};
        expect(byId[first.id], isFalse);
        expect(byId[second.id], isTrue);
      },
    );

    test('updateAddress(makeDefault: true) atomically promotes an existing '
        'address to default in the SAME write as its field update', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);

      final first = await repo.addAddress(_draft(fullName: 'First'));
      final second = await repo.addAddress(_draft(fullName: 'Second'));
      await _waitForNotify(repo, () async {});

      final updated = second.copyWith(fullName: 'Second Updated');
      await _waitForNotify(
        repo,
        () => repo.updateAddress(updated, makeDefault: true),
      );

      final byId = {for (final a in repo.addresses) a.id: a};
      expect(byId[first.id]!.isDefault, isFalse);
      expect(byId[second.id]!.isDefault, isTrue);
      expect(byId[second.id]!.fullName, 'Second Updated');
    });

    test('a malformed defaultAddressId (present but wrong type) is '
        'ignored, never crashes the listener', () async {
      final auth = _sessionFor('alice');
      await firestore
          .collection('users')
          .doc('alice')
          .collection('addresses')
          .doc('a1')
          .set({
            'fullName': 'First',
            'phoneNumber': '1',
            'addressLine1': 'L1',
            'city': 'C',
            'provinceOrState': 'P',
            'postalCode': '0',
            'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          });
      await firestore
          .collection('users')
          .doc('alice')
          .collection('addressDefault')
          .doc('pointer')
          .set({'defaultAddressId': 12345}); // wrong type - not a String

      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      await _waitForNotify(repo, () async {});

      // Never throws, and never falsely matches the malformed value.
      expect(repo.addresses.single.isDefault, isFalse);
      expect(repo.defaultAddress, isNull);
      expect(repo.hasError, isFalse);
    });

    test('isLoading only clears once BOTH the addresses AND the pointer '
        'subscription have delivered their first snapshot for the current '
        'generation', () async {
      final auth = _sessionFor('alice');
      final repo = FirestoreAddressRepository(auth, firestore: firestore);

      expect(repo.isLoading, isTrue);

      final generation = repo.debugGeneration;
      // Only the addresses subscription "arrives" - the pointer has not.
      repo.debugSimulateAddressesSnapshot(generation, const []);
      expect(
        repo.isLoading,
        isTrue,
        reason:
            'must still report loading - the pointer snapshot has not '
            'arrived yet, so `addresses`\' isDefault values are not yet '
            'trustworthy',
      );

      repo.debugSimulatePointerSnapshot(generation, null);
      expect(repo.isLoading, isFalse);
    });

    test('a null default pointer with addresses still present is '
        'self-healed by the reconciliation safety net that runs after '
        'every delete - closes the "concurrent add during delete-of-only-'
        'address" race (see FirestoreAddressRepository.deleteAddress\'s '
        'doc comment)', () async {
      final auth = _sessionFor('alice');
      final collection = firestore
          .collection('users')
          .doc('alice')
          .collection('addresses');
      await collection.doc('a1').set({
        'fullName': 'First',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
      });
      await collection.doc('a2').set({
        'fullName': 'Second',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 2)),
      });
      await collection.doc('a3').set({
        'fullName': 'Third',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': Timestamp.fromDate(DateTime(2026, 1, 3)),
      });
      // Simulate the exact broken state the race would produce: addresses
      // exist but the pointer is null.
      await firestore
          .collection('users')
          .doc('alice')
          .collection('addressDefault')
          .doc('pointer')
          .set({'defaultAddressId': null});

      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      await _waitForNotify(repo, () async {});
      expect(repo.defaultAddress, isNull); // confirms the broken state loaded

      // Delete a NON-default address - `deleteAddress`'s own
      // default-reassign branch is never triggered (wasDefault is false for
      // a3), but the unconditional post-delete reconciliation safety net
      // still runs and self-heals the dangling null pointer.
      await _waitForNotify(repo, () => repo.deleteAddress('a3'));

      expect(repo.defaultAddress, isNotNull);
      expect(repo.defaultAddress!.id, 'a1'); // earliest remaining
    });

    test('addresses breaks a createdAt tie deterministically by document '
        'ID, not by insertion/listener order', () async {
      final auth = _sessionFor('alice');
      final tie = Timestamp.fromDate(DateTime(2026, 1, 1));
      final collection = firestore
          .collection('users')
          .doc('alice')
          .collection('addresses');
      await collection.doc('z-addr').set({
        'fullName': 'Z',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': tie,
      });
      await collection.doc('a-addr').set({
        'fullName': 'A',
        'phoneNumber': '1',
        'addressLine1': 'L1',
        'city': 'C',
        'provinceOrState': 'P',
        'postalCode': '0',
        'createdAt': tie,
      });

      final repo = FirestoreAddressRepository(auth, firestore: firestore);
      await _waitForNotify(repo, () async {});

      expect(repo.addresses.map((a) => a.id).toList(), ['a-addr', 'z-addr']);
    });
  });
}
