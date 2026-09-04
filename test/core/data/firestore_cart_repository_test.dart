import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/cart_repository.dart';
import 'package:twin_ar/core/data/firestore_cart_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_size.dart';
import 'package:twin_ar/core/utils/cart_item_key.dart';

/// Waits until [notifier] has gone quiet (at least one notify has occurred,
/// and no further notify arrives for a short grace period) - robust against
/// an unrelated notify (e.g. the initial empty-snapshot event still
/// in-flight from construction) resolving this wait before the mutation
/// under test has actually landed.
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

AuthSessionState _sessionFor(String uid) => AuthSessionState()
  ..setSession(
    AuthResult.success(
      userId: uid,
      email: '$uid@x.com',
      role: UserRole.customer,
    ),
  );

void main() {
  group('FirestoreCartRepository', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('addItem creates a new line keyed by the deterministic hashed '
        'tuple key, never the raw local composite id', () async {
      final repo = FirestoreCartRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await _waitForNotify(
        repo,
        () => repo.addItem(
          productId: 'p1',
          quantity: 2,
          selectedColor: ProductColorOption.blue,
          selectedSize: ProductSize.m,
        ),
      );

      expect(repo.items.single.productId, 'p1');
      expect(repo.items.single.quantity, 2);

      final expectedKey = cartItemFirestoreKey(
        productId: 'p1',
        selectedColor: ProductColorOption.blue.name,
        selectedSize: ProductSize.m.name,
      );
      final doc = await firestore
          .collection('users')
          .doc('alice')
          .collection('cart')
          .doc(expectedKey)
          .get();
      expect(doc.exists, isTrue);
    });

    test('adding the same product/variant twice merges (sums) quantity in '
        'a single Firestore document, never creating a duplicate', () async {
      final repo = FirestoreCartRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await repo.addItem(productId: 'p1', quantity: 2);
      await _waitForNotify(
        repo,
        () => repo.addItem(productId: 'p1', quantity: 3),
      );

      expect(repo.items.length, 1);
      expect(repo.items.single.quantity, 5);
    });

    // A genuinely CONCURRENT pair of addItem calls for the same
    // product/variant (Future.wait, not awaited sequentially) is NOT
    // exercised here: `fake_cloud_firestore` does not emulate Firestore's
    // real optimistic-concurrency conflict detection/retry for two
    // overlapping `runTransaction` calls racing the same not-yet-existing
    // document - both transactions observe "doc doesn't exist" and both
    // take the create branch, so the second write simply overwrites the
    // first (last-write-wins) instead of merging, which would fail this
    // test against the fake even though the real implementation is
    // correct. The authoritative proof that two devices' concurrent adds
    // converge on the summed quantity against REAL Firestore semantics is
    // `firestore-tests/run_rules_tests.mjs`'s "cart/{cartItemKey} -
    // concurrent atomic quantity merge" test, which runs against the real
    // Firebase Local Emulator Suite (full transaction-conflict-retry
    // fidelity) rather than this fake. The SEQUENTIAL merge case above
    // ("adding the same product/variant twice merges...") already proves
    // this class's merge LOGIC itself is correct; only true concurrent
    // conflict-retry is out of reach of this fake.

    test('quantity is clamped to cartMaxQuantity even under a merge that '
        'would otherwise exceed it', () async {
      final repo = FirestoreCartRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await repo.addItem(productId: 'p1', quantity: 90);
      await _waitForNotify(
        repo,
        () => repo.addItem(productId: 'p1', quantity: 90),
      );
      expect(repo.items.single.quantity, cartMaxQuantity);
    });

    test('setQuantity sets an absolute quantity; a value below the minimum '
        'is a no-op, never a removal', () async {
      final repo = FirestoreCartRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await repo.addItem(productId: 'p1', quantity: 1);
      await _waitForNotify(
        repo,
        () => repo.setQuantity(productId: 'p1', quantity: 10),
      );
      expect(repo.items.single.quantity, 10);

      await repo.setQuantity(productId: 'p1', quantity: 0);
      expect(repo.items.single.quantity, 10);
    });

    test('removeItem removes exactly the matching variant', () async {
      final repo = FirestoreCartRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await repo.addItem(
        productId: 'p1',
        selectedColor: ProductColorOption.blue,
      );
      await repo.addItem(
        productId: 'p1',
        selectedColor: ProductColorOption.black,
      );
      await _waitForNotify(
        repo,
        () => repo.removeItem(
          productId: 'p1',
          selectedColor: ProductColorOption.blue,
        ),
      );
      expect(repo.items.length, 1);
      expect(repo.items.single.selectedColor, ProductColorOption.black);
    });

    test('clear empties the cart, re-querying fresh rather than trusting '
        'the local cache', () async {
      final repo = FirestoreCartRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await repo.addItem(productId: 'p1');
      await repo.addItem(productId: 'p2');
      await _waitForNotify(repo, () => repo.clear());
      expect(repo.items, isEmpty);
    });

    test('a malformed cart line does not block the rest of the cart from '
        'loading', () async {
      final collection = firestore
          .collection('users')
          .doc('alice')
          .collection('cart');
      await collection.doc('good').set({'productId': 'p1', 'quantity': 2});
      await collection.doc('bad').set({
        'productId': 12345, // wrong type
        'quantity': 'not-a-number',
      });

      final repo = FirestoreCartRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await _waitForNotify(repo, () async {});

      // Both lines map defensively (never throw) - the mapper falls back
      // to safe defaults rather than skipping, so both are present; the
      // key guarantee under test is that the malformed one never crashes
      // the listener or hides the good one.
      expect(
        repo.items.any((i) => i.productId == 'p1' && i.quantity == 2),
        isTrue,
      );
    });

    test(
      'signed-out mutations fail cleanly, no local shared state created',
      () async {
        final repo = FirestoreCartRepository(
          AuthSessionState(),
          firestore: firestore,
        );
        await expectLater(
          repo.addItem(productId: 'p1'),
          throwsA(isA<StateError>()),
        );
        expect(repo.items, isEmpty);
      },
    );

    test('a direct Customer A -> Customer B switch never shows A\'s cart '
        'to B', () async {
      await firestore
          .collection('users')
          .doc('alice')
          .collection('cart')
          .doc('a-item')
          .set({'productId': 'alice-product', 'quantity': 1});
      await firestore
          .collection('users')
          .doc('bob')
          .collection('cart')
          .doc('b-item')
          .set({'productId': 'bob-product', 'quantity': 1});

      final auth = _sessionFor('alice');
      final repo = FirestoreCartRepository(auth, firestore: firestore);
      await _waitForNotify(repo, () async {});
      expect(repo.items.single.productId, 'alice-product');

      await _waitForNotify(repo, () async {
        auth.setSession(
          AuthResult.success(
            userId: 'bob',
            email: 'bob@x.com',
            role: UserRole.customer,
          ),
        );
      });

      expect(repo.items.single.productId, 'bob-product');
    });

    test(
      'a stale-generation snapshot callback is dropped, never applied',
      () async {
        final repo = FirestoreCartRepository(
          _sessionFor('alice'),
          firestore: firestore,
        );
        await _waitForNotify(repo, () async {});

        final staleGeneration = repo.debugGeneration - 1;
        repo.debugSimulateSnapshot(staleGeneration, [
          MapEntry('intruder', {
            'productId': 'intruder-product',
            'quantity': 1,
          }),
        ]);

        expect(
          repo.items.any((i) => i.productId == 'intruder-product'),
          isFalse,
        );
      },
    );

    test('a transient listener error for the CURRENT uid preserves the '
        'last-good cache', () async {
      final repo = FirestoreCartRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await _waitForNotify(
        repo,
        () => repo.addItem(productId: 'p1', quantity: 2),
      );
      expect(repo.items, isNotEmpty);

      repo.debugSimulateError(repo.debugGeneration);

      expect(repo.hasError, isTrue);
      expect(repo.items.single.productId, 'p1');
    });
  });
}
