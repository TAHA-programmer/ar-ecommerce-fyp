import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../app/viewmodels/auth_session_state.dart';
import '../../features/cart/models/cart_item_model.dart';
import '../models/product/product_color_option.dart';
import '../models/product/product_size.dart';
import '../utils/cart_item_key.dart';
import 'cart_firestore_mapper.dart';
import 'cart_repository.dart';

/// Firestore-backed [CartRepository] (Phase 8.10). Owner-scoped (uid-keyed)
/// live subscription with a monotonic generation guard - same shape and
/// same uid-isolation guarantees as [FirestoreAddressRepository]/
/// [FirestoreFavoritesRepository]; see the former's doc comment for the
/// full rationale (not repeated here).
///
/// **Deterministic, collision-safe document IDs.** The existing
/// `CartItemModel.id` getter (`'${productId}_${colorStr}_$sizeStr'`) is a
/// fine LOCAL map key but is never used directly as a Firestore document
/// ID here - see `cart_item_key.dart`'s doc comment for why a hashed key
/// derived from the canonical `(productId, selectedColor, selectedSize)`
/// tuple is used instead. Two devices adding the exact same product+variant
/// always resolve to the exact same document.
///
/// **Atomic quantity merge.** [addItem] runs inside a Firestore transaction:
/// reads the target document, and if it already exists, WRITES
/// `existingQuantity + requestedQuantity` (clamped to [cartMaxQuantity]) -
/// never a blind overwrite. Two devices adding the same product/variant at
/// the same time therefore always converge on the correctly SUMMED
/// quantity, never one add silently clobbering the other (a race a plain
/// non-transactional `.set()` would be vulnerable to).
class FirestoreCartRepository extends CartRepository {
  final AuthSessionState _authSessionState;
  final FirebaseFirestore _firestore;

  List<MapEntry<String, Map<String, dynamic>>> _rawDocs = [];
  bool _isLoading = true;
  bool _hasError = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _lastUid;
  int _generation = 0;

  FirestoreCartRepository(
    this._authSessionState, {
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _authSessionState.addListener(_onAuthChanged);
    _subscribe();
  }

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _firestore.collection('users').doc(uid).collection('cart');

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
  List<CartItemModel> get items {
    // One malformed line must never crash/hide the rest of the cart (Phase
    // 8.10 requirement) - each document is mapped independently and a
    // failure is skipped, not propagated.
    final result = <CartItemModel>[];
    for (final entry in _rawDocs) {
      try {
        result.add(cartItemModelFromFirestore(entry.value));
      } catch (_) {
        // Skip this one malformed line only.
      }
    }
    return List.unmodifiable(result);
  }

  @override
  Future<void> addItem({
    required String productId,
    int quantity = 1,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
    int priceAmountSnapshot = 0,
  }) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');
    final requested = quantity.clamp(cartMinQuantity, cartMaxQuantity);
    final docRef = _collection(uid).doc(
      cartItemFirestoreKey(
        productId: productId,
        selectedColor: selectedColor?.name,
        selectedSize: selectedSize?.name,
      ),
    );

    await _firestore.runTransaction((transaction) async {
      final snap = await transaction.get(docRef);
      if (snap.exists) {
        final existingQuantity =
            (snap.data()?['quantity'] as num?)?.toInt() ?? 0;
        final merged = (existingQuantity + requested).clamp(
          cartMinQuantity,
          cartMaxQuantity,
        );
        transaction.update(
          docRef,
          cartItemToFirestoreUpdateMap(
            quantity: merged,
            priceAmountSnapshot: priceAmountSnapshot,
          ),
        );
      } else {
        transaction.set(
          docRef,
          cartItemToFirestoreCreateMap(
            productId: productId,
            quantity: requested,
            selectedColor: selectedColor,
            selectedSize: selectedSize,
            priceAmountSnapshot: priceAmountSnapshot,
          ),
        );
      }
    });
  }

  @override
  Future<void> setQuantity({
    required String productId,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
    required int quantity,
  }) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');
    if (quantity < cartMinQuantity) return;
    final docRef = _collection(uid).doc(
      cartItemFirestoreKey(
        productId: productId,
        selectedColor: selectedColor?.name,
        selectedSize: selectedSize?.name,
      ),
    );
    await docRef.update(
      cartItemToFirestoreUpdateMap(
        quantity: quantity.clamp(cartMinQuantity, cartMaxQuantity),
      ),
    );
  }

  @override
  Future<void> removeItem({
    required String productId,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
  }) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');
    final docRef = _collection(uid).doc(
      cartItemFirestoreKey(
        productId: productId,
        selectedColor: selectedColor?.name,
        selectedSize: selectedSize?.name,
      ),
    );
    await docRef.delete();
  }

  @override
  Future<void> clear() async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');
    // Re-queries fresh rather than trusting the local cache, so a very
    // recent add that hasn't reached this listener yet is still cleared.
    final snapshot = await _collection(uid).get();
    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  @override
  void dispose() {
    _generation++;
    _subscription?.cancel();
    _authSessionState.removeListener(_onAuthChanged);
    super.dispose();
  }
}
