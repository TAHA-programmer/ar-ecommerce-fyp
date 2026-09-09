import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/product_details/repositories/firestore_recently_viewed_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_recently_viewed_repository.dart';

AuthSessionState _session(String? uid) {
  final s = AuthSessionState();
  if (uid != null) {
    s.setSession(
      AuthResult.success(
        userId: uid,
        email: '$uid@x.com',
        role: UserRole.customer,
      ),
    );
  }
  return s;
}

void main() {
  group('MockRecentlyViewedRepository', () {
    test(
      'dedups by product ID and moves a re-viewed product to the front',
      () async {
        final r = MockRecentlyViewedRepository();
        await r.recordView('a');
        await r.recordView('b');
        await r.recordView('c');
        expect(await r.recentProductIds(), ['c', 'b', 'a']);

        await r.recordView('a'); // revisit
        expect(await r.recentProductIds(), ['a', 'c', 'b']);
      },
    );

    test('caps history at keepNewest', () async {
      final r = MockRecentlyViewedRepository(keepNewest: 3);
      for (final id in ['a', 'b', 'c', 'd', 'e']) {
        await r.recordView(id);
      }
      expect(await r.recentProductIds(), ['e', 'd', 'c']);
    });

    test('is a no-op when signed out', () async {
      final r = MockRecentlyViewedRepository(signedIn: false);
      await r.recordView('a');
      expect(await r.recentProductIds(), isEmpty);
      expect(r.recordedViews, ['a']); // the call was made, just not stored
    });

    test('swallows a failing write', () async {
      final r = MockRecentlyViewedRepository()..failNext = true;
      await r.recordView('a'); // must not throw
      expect(await r.recentProductIds(), isEmpty);
    });
  });

  group('FirestoreRecentlyViewedRepository', () {
    late FakeFirebaseFirestore firestore;

    setUp(() => firestore = FakeFirebaseFirestore());

    test(
      'records a view under the signed-in user, dedups + moves to front',
      () async {
        final repo = FirestoreRecentlyViewedRepository(
          _session('u1'),
          firestore: firestore,
        );
        await repo.recordView('p1');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await repo.recordView('p2');
        await Future<void>.delayed(const Duration(milliseconds: 1));
        await repo.recordView('p1'); // revisit

        final ids = await repo.recentProductIds();
        expect(ids, ['p1', 'p2']);

        final docs = await firestore
            .collection('users')
            .doc('u1')
            .collection('recentlyViewed')
            .get();
        expect(docs.docs.map((d) => d.id).toSet(), {'p1', 'p2'});
        expect(docs.docs.first.data().keys, ['viewedAt']);
      },
    );

    test('is a silent no-op when signed out', () async {
      final repo = FirestoreRecentlyViewedRepository(
        _session(null),
        firestore: firestore,
      );
      await repo.recordView('p1'); // must not throw
      expect(await repo.recentProductIds(), isEmpty);
    });

    test('recentProductIds respects the limit, newest first', () async {
      final repo = FirestoreRecentlyViewedRepository(
        _session('u1'),
        firestore: firestore,
      );
      for (final id in ['a', 'b', 'c', 'd']) {
        await repo.recordView(id);
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(await repo.recentProductIds(limit: 2), ['d', 'c']);
    });

    test('an empty productId is ignored', () async {
      final repo = FirestoreRecentlyViewedRepository(
        _session('u1'),
        firestore: firestore,
      );
      await repo.recordView('');
      expect(await repo.recentProductIds(), isEmpty);
    });

    test('amortised pruning keeps the collection at the newest 30 (bounded '
        'read) and keeps the very newest', () async {
      final repo = FirestoreRecentlyViewedRepository(
        _session('u1'),
        firestore: firestore,
      );
      // 50 distinct views → prune runs at #10/#20/#30/#40/#50; each pass
      // reads at most 60 docs and trims back to exactly 30.
      for (var i = 0; i < 50; i++) {
        await repo.recordView('p${i.toString().padLeft(2, '0')}');
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }

      final docs = await firestore
          .collection('users')
          .doc('u1')
          .collection('recentlyViewed')
          .get();
      expect(docs.docs.length, 30);

      final newest = await repo.recentProductIds(limit: 3);
      expect(newest, ['p49', 'p48', 'p47']);
    });
  });
}
