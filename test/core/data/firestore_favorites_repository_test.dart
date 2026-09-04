import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/firestore_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';

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
  group('FirestoreFavoritesRepository', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test(
      'addFavorite then isFavorite reflects it after the live snapshot',
      () async {
        final repo = FirestoreFavoritesRepository(
          _sessionFor('alice'),
          firestore: firestore,
        );
        await _waitForNotify(repo, () => repo.addFavorite('p1'));
        expect(repo.isFavorite('p1'), isTrue);
      },
    );

    test('document ID is the productId - re-favoriting is idempotent, '
        'never a duplicate', () async {
      final repo = FirestoreFavoritesRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await _waitForNotify(repo, () => repo.addFavorite('p1'));
      await repo.addFavorite('p1');
      expect(repo.favorites.length, 1);
    });

    test('removeFavorite removes it', () async {
      final repo = FirestoreFavoritesRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await _waitForNotify(repo, () => repo.addFavorite('p1'));
      await _waitForNotify(repo, () => repo.removeFavorite('p1'));
      expect(repo.isFavorite('p1'), isFalse);
    });

    test(
      'signed-out mutations fail cleanly, no local shared state created',
      () async {
        final repo = FirestoreFavoritesRepository(
          AuthSessionState(),
          firestore: firestore,
        );
        await expectLater(repo.addFavorite('p1'), throwsA(isA<StateError>()));
        expect(repo.favorites, isEmpty);
      },
    );

    test('a direct Customer A -> Customer B switch never shows A\'s '
        'favorites to B', () async {
      await firestore
          .collection('users')
          .doc('alice')
          .collection('favorites')
          .doc('alice-fav')
          .set({'addedAt': Timestamp.fromDate(DateTime(2026, 1, 1))});
      await firestore
          .collection('users')
          .doc('bob')
          .collection('favorites')
          .doc('bob-fav')
          .set({'addedAt': Timestamp.fromDate(DateTime(2026, 1, 1))});

      final auth = _sessionFor('alice');
      final repo = FirestoreFavoritesRepository(auth, firestore: firestore);
      await _waitForNotify(repo, () async {});
      expect(repo.favoriteProductIds, {'alice-fav'});

      await _waitForNotify(repo, () async {
        auth.setSession(
          AuthResult.success(
            userId: 'bob',
            email: 'bob@x.com',
            role: UserRole.customer,
          ),
        );
      });

      expect(repo.favoriteProductIds, {'bob-fav'});
    });

    test(
      'a stale-generation snapshot callback is dropped, never applied',
      () async {
        final repo = FirestoreFavoritesRepository(
          _sessionFor('alice'),
          firestore: firestore,
        );
        await _waitForNotify(repo, () async {});

        final staleGeneration = repo.debugGeneration - 1;
        repo.debugSimulateSnapshot(staleGeneration, [
          MapEntry('intruder', {
            'addedAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
          }),
        ]);

        expect(repo.isFavorite('intruder'), isFalse);
      },
    );

    test('a transient listener error for the CURRENT uid preserves the '
        'last-good cache', () async {
      final repo = FirestoreFavoritesRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await _waitForNotify(repo, () => repo.addFavorite('p1'));
      expect(repo.favoriteProductIds, {'p1'});

      repo.debugSimulateError(repo.debugGeneration);

      expect(repo.hasError, isTrue);
      expect(repo.favoriteProductIds, {'p1'});
    });

    test('a bad/unavailable favorite product lookup never removes the '
        'favorite itself - this repository never auto-deletes based on '
        'resolution outcomes', () async {
      // FavoritesRepository has no concept of "product lookup failed" at
      // all - it only ever stores/removes a favorite in response to an
      // explicit addFavorite/removeFavorite call. This test documents that
      // structural guarantee: nothing in this class's write surface is
      // triggered by a product-resolution failure (that isolation lives one
      // layer up, in FavoritesViewModel - see favorites_viewmodel_test.dart
      // and the Phase 8.10 fix in favorites_viewmodel.dart).
      final repo = FirestoreFavoritesRepository(
        _sessionFor('alice'),
        firestore: firestore,
      );
      await _waitForNotify(repo, () => repo.addFavorite('deleted-product'));
      expect(repo.isFavorite('deleted-product'), isTrue);
    });
  });
}
