import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../app/viewmodels/auth_session_state.dart';
import '../models/favorite/favorite_model.dart';
import 'favorite_firestore_mapper.dart';
import 'favorites_repository.dart';

/// Firestore-backed [FavoritesRepository] (Phase 8.10). Owner-scoped
/// (uid-keyed) live subscription with a monotonic generation guard - same
/// shape and same uid-isolation guarantees as [FirestoreAddressRepository];
/// see that class's doc comment for the full rationale (this class omits
/// repeating it).
///
/// Document ID == productId, so `addFavorite`/`removeFavorite` naturally
/// converge on the exact same document for the same product - no
/// merge/collision concern the way cart items have. `removeFavorite` is a
/// plain, idempotent `.delete()`. `addFavorite` is NOT a plain `.set()`,
/// despite that looking idempotent at first glance - see its own doc
/// comment for why a transaction is required instead (Security Rules
/// classify a `.set()` on an already-existing document as an `update`, and
/// `favorites/{id}` locks `allow update: if false`).
class FirestoreFavoritesRepository extends FavoritesRepository {
  final AuthSessionState _authSessionState;
  final FirebaseFirestore _firestore;

  List<MapEntry<String, Map<String, dynamic>>> _rawDocs = [];
  bool _isLoading = true;
  bool _hasError = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _lastUid;
  int _generation = 0;

  FirestoreFavoritesRepository(
    this._authSessionState, {
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _authSessionState.addListener(_onAuthChanged);
    _subscribe();
  }

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _firestore.collection('users').doc(uid).collection('favorites');

  String? get _currentUid =>
      _authSessionState.isAuthenticated ? _authSessionState.userId : null;

  void _onAuthChanged() {
    if (_currentUid == _lastUid) return;
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    final uid = _currentUid;
    _lastUid = uid;
    final generation = ++_generation;

    _rawDocs = [];
    _hasError = false;

    if (uid == null) {
      _subscription = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    _subscription = _collection(uid).snapshots().listen(
      (snapshot) => _onSnapshot(
        generation,
        snapshot.docs.map((d) => MapEntry(d.id, d.data())).toList(),
      ),
      onError: (_) => _onError(generation),
    );
  }

  bool _isStale(int generation) => generation != _generation;

  void _onSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    if (_isStale(generation)) return;
    _rawDocs = docs;
    _isLoading = false;
    _hasError = false;
    notifyListeners();
  }

  /// Transient error for the CURRENT uid preserves the last-known list
  /// (never silently looks like "you have no favorites") - the generation
  /// guard already prevents this from ever resurrecting a PREVIOUS uid's
  /// data.
  void _onError(int generation) {
    if (_isStale(generation)) return;
    _hasError = true;
    _isLoading = false;
    notifyListeners();
  }

  @visibleForTesting
  void debugSimulateSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) => _onSnapshot(generation, docs);

  @visibleForTesting
  void debugSimulateError(int generation) => _onError(generation);

  @visibleForTesting
  int get debugGeneration => _generation;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasError => _hasError;

  @override
  List<FavoriteModel> get favorites {
    final mapped = _rawDocs
        .map((e) => favoriteModelFromFirestore(e.key, e.value))
        .toList();
    mapped.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    return List.unmodifiable(mapped);
  }

  /// **Pre-deployment correction (found by independent review):** a plain
  /// `.set()` here used to be classified by Security Rules as an `update`
  /// whenever the target document ALREADY existed (rules distinguish
  /// create/update by whether the document existed before the write, not by
  /// which client API issued it) - but `favorites/{id}`'s rule is `allow
  /// update: if false`, so re-favoriting an already-favorited product used
  /// to fail `permission-denied` against the REAL rules, even though this
  /// method's own interface docs (and a `fake_cloud_firestore` test that
  /// doesn't enforce the create/update distinction the same way) both
  /// claimed it was idempotent. Fixed: a transaction reads the document
  /// first and only ever issues a `create`-classified write when it's
  /// genuinely absent - a repeat/concurrent favorite of the same product now
  /// correctly completes with zero additional writes instead of hitting the
  /// locked-down update rule.
  @override
  Future<void> addFavorite(String productId) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');
    final docRef = _collection(uid).doc(productId);
    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      if (snap.exists) return; // already favorited - no write at all.
      transaction.set(docRef, favoriteToFirestoreCreateMap());
    });
  }

  @override
  Future<void> removeFavorite(String productId) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');
    await _collection(uid).doc(productId).delete();
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    _authSessionState.removeListener(_onAuthChanged);
    super.dispose();
  }
}
