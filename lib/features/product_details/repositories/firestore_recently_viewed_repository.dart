import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import 'recently_viewed_repository.dart';

/// Firestore-backed [RecentlyViewedRepository]. Owner-scoped: every read/write
/// is under the currently signed-in user's own
/// `users/{uid}/recentlyViewed/{productId}` subcollection, which is exactly
/// what `firestore.rules` enforces (`isOwner(uid)`).
///
/// There is **no live subscription** here — Stage 2 only records views, and
/// Stage 3's Home read is a one-shot `recentProductIds()` (Home re-derives on
/// its own `_onDbChanged` cadence). Keeping this a plain writer + one-shot
/// reader avoids another always-on listener.
class FirestoreRecentlyViewedRepository implements RecentlyViewedRepository {
  final AuthSessionState _authSessionState;
  final FirebaseFirestore _firestore;

  /// Best-effort pruning is amortised — only run every [_pruneEvery]th
  /// `recordView`, since the collection is naturally bounded near
  /// [_keepNewest] anyway.
  static const int _keepNewest = 30;
  static const int _pruneEvery = 10;

  /// The prune read is bounded to this many documents. A `recordView` adds at
  /// most one *new* doc (a re-view overwrites), so between two prunes the
  /// collection grows by at most [_pruneEvery]; this window (3× that over
  /// [_keepNewest]) always contains the whole overflow in normal operation,
  /// so a single prune restores the newest-[_keepNewest] invariant exactly.
  /// If a long run of prune failures ever let it grow past the window,
  /// successive prunes still walk it back down — just over more calls.
  static const int _pruneScanLimit = _keepNewest + _pruneEvery * 3;
  int _writesSincePrune = 0;

  FirestoreRecentlyViewedRepository(
    this._authSessionState, {
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>>? _collection() {
    if (!_authSessionState.isAuthenticated) return null;
    final uid = _authSessionState.userId;
    if (uid == null) return null;
    return _firestore.collection('users').doc(uid).collection('recentlyViewed');
  }

  @override
  Future<void> recordView(String productId) async {
    if (productId.isEmpty) return;
    final col = _collection();
    if (col == null) return; // signed out — nothing to record.
    try {
      // Doc ID == productId → this both dedupes and moves the product to the
      // front (newest `viewedAt`). `.set` works whether the doc exists or
      // not; `firestore.rules` allows both create and update with the
      // `{ viewedAt: request.time }` shape.
      await col.doc(productId).set({'viewedAt': FieldValue.serverTimestamp()});
      _writesSincePrune++;
      if (_writesSincePrune >= _pruneEvery) {
        _writesSincePrune = 0;
        await _pruneOldest(col);
      }
    } catch (_) {
      // Fire-and-forget: a failed view write must never disturb Product
      // Details. Swallow.
    }
  }

  Future<void> _pruneOldest(
    CollectionReference<Map<String, dynamic>> col,
  ) async {
    try {
      // Bounded read: newest [_pruneScanLimit] only. `batch.delete` on a doc
      // a concurrent prune (another device) already removed is a no-op, so
      // overlapping prunes are safe.
      final snap = await col
          .orderBy('viewedAt', descending: true)
          .limit(_pruneScanLimit)
          .get();
      if (snap.docs.length <= _keepNewest) return;
      final batch = _firestore.batch();
      for (final doc in snap.docs.skip(_keepNewest)) {
        batch.delete(doc.reference);
      }
      await batch.commit();
    } catch (_) {
      // Best-effort only.
    }
  }

  @override
  Future<List<String>> recentProductIds({int limit = 12}) async {
    final col = _collection();
    if (col == null) return const [];
    try {
      final snap = await col
          .orderBy('viewedAt', descending: true)
          .limit(limit)
          .get();
      return snap.docs.map((d) => d.id).toList(growable: false);
    } catch (_) {
      return const [];
    }
  }
}
