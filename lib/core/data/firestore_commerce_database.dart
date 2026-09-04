import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../app/viewmodels/auth_session_state.dart';
import '../models/order/order_model.dart';
import '../models/order/payment_record.dart';
import '../models/product/product_model.dart';
import 'commerce_database.dart';
import 'order_firestore_mapper.dart';
import 'payment_firestore_mapper.dart';
import 'product_firestore_mapper.dart';

/// The three distinct product-visibility identities `firestore.rules`
/// actually distinguishes for `products/{id}` reads. See
/// [FirestoreCommerceDatabase]'s doc comment for why this - not a bare
/// `isSuperAdmin` bool - is what must be tracked across auth-state changes.
enum _QueryKind { signedOut, customer, admin }

/// Phase 8.9: identity tracked for the orders/payments subscriptions -
/// deliberately a SEPARATE tracked value from [_QueryKind], not reused for
/// it, even though both are computed from the same [AuthSessionState].
///
/// [_QueryKind] alone is correct for products (the query shape never
/// depends on *which* customer is signed in, only on *whether* the caller
/// is an admin/customer/signed-out), but it is NOT sufficient for
/// orders/payments: two different customers share `kind == customer`, so a
/// direct Customer A -> Customer B switch (same role, different uid) would
/// be invisible to a bare kind comparison and could leave Customer A's
/// orders/payments in the cache while Customer B's session is active. This
/// class folds `uid` into the identity so ANY uid change - even with the
/// role unchanged - is detected and triggers a re-subscribe.
class _OrdersIdentity {
  final _QueryKind kind;
  final String? uid;
  const _OrdersIdentity(this.kind, this.uid);

  @override
  bool operator ==(Object other) =>
      other is _OrdersIdentity && other.kind == kind && other.uid == uid;

  @override
  int get hashCode => Object.hash(kind, uid);
}

/// Firestore-backed [CommerceDatabase]. Product reads (Phase 8.5),
/// product-catalog writes (Phase 8.6), and orders/payments reads (Phase 8.9)
/// are all real. Phase 8.13.6 (Final Security Cutover) removed the last
/// client write paths for commerce data: orders, payments and checkout stock
/// reservations are created only by the Cloud Functions now, so this class
/// exposes no `submitOrderWithPayment` / `recordOrderStockDecrement` - it is
/// a read cache for `orders`/`payments` plus the Admin product-catalog and
/// order-status writes.
///
/// Why product reads need to know the caller's role: `getProductById`/
/// `products` are synchronous getters (the whole point of the
/// [CommerceDatabase] contract - see its doc comment), so they must be
/// backed by an already-populated local cache, not a query-per-call. Admin
/// needs the full catalog (drafts/inactive included); a signed-in customer
/// can only be granted a `published && isActive` collection-wide LIST query
/// by `firestore.rules` (an unfiltered list query is rejected outright for
/// a non-admin - Firestore requires list queries to be provably rule-safe);
/// a signed-out session is denied both queries entirely
/// (`firestore.rules` requires `isSignedIn()` in every branch). One shared
/// cache therefore can't serve all three states without knowing which one
/// currently applies, so this class re-subscribes with a different query -
/// or no query at all - whenever that identity changes.
///
/// `orders`/`payments` (Phase 8.9) follow the same shape but are further
/// scoped by uid for a customer - see [_OrdersIdentity].
class FirestoreCommerceDatabase extends CommerceDatabase {
  final AuthSessionState _authSessionState;
  final FirebaseFirestore _firestore;

  List<ProductModel> _products = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _productsSubscription;
  _QueryKind? _lastQueryKind;

  List<OrderModel> _orders = [];
  List<PaymentRecord> _payments = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ordersSubscription;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _paymentsSubscription;
  _OrdersIdentity? _lastOrdersIdentity;

  /// Bumped on every [_subscribeOrdersAndPayments] call; each snapshot/error
  /// handler captures its own generation at subscribe time and silently
  /// drops a callback whose generation is stale before touching `_orders`/
  /// `_payments` or calling [notifyListeners] - mirrors
  /// `FirestoreCategoryRepository`'s Phase 8.8 hardening-pass pattern.
  /// `StreamSubscription.cancel()` is asynchronous and cannot guarantee an
  /// in-flight event from an old identity's listener is discarded before a
  /// new identity's listener starts receiving events.
  int _ordersGeneration = 0;

  /// True after a transient orders/payments listener error - the LAST
  /// successfully-loaded cache is deliberately preserved (see
  /// [_onOrdersError]'s doc comment), so this flag is how a UI could
  /// optionally surface "showing possibly-stale data" without this class
  /// silently replacing real order history with an indistinguishable empty
  /// list.
  bool hasOrdersError = false;
  bool hasPaymentsError = false;

  FirestoreCommerceDatabase(
    this._authSessionState, {
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _authSessionState.addListener(_onAuthChanged);
    _subscribeProducts();
    _subscribeOrdersAndPayments();
  }

  CollectionReference<Map<String, dynamic>> get _productsCollection =>
      _firestore.collection('products');
  CollectionReference<Map<String, dynamic>> get _ordersCollection =>
      _firestore.collection('orders');
  CollectionReference<Map<String, dynamic>> get _paymentsCollection =>
      _firestore.collection('payments');

  _QueryKind get _currentQueryKind {
    if (!_authSessionState.isAuthenticated) return _QueryKind.signedOut;
    return _authSessionState.isSuperAdmin
        ? _QueryKind.admin
        : _QueryKind.customer;
  }

  _OrdersIdentity get _currentOrdersIdentity =>
      _OrdersIdentity(_currentQueryKind, _authSessionState.userId);

  /// Phase 8.9 correction: product-role re-subscription and orders/payments
  /// identity re-subscription are independent checks, NOT a single early
  /// return keyed on `_QueryKind` alone. `_QueryKind` is sufficient for
  /// products (see the class doc comment) but NOT for orders/payments - a
  /// Customer A -> Customer B switch never changes `_QueryKind` (both are
  /// `customer`), so an early `if (_currentQueryKind == _lastQueryKind)
  /// return;` guarding the whole method would have skipped the
  /// orders/payments re-subscribe entirely for that transition. Each check
  /// runs and decides for itself.
  void _onAuthChanged() {
    if (_currentQueryKind != _lastQueryKind) {
      _subscribeProducts();
    }
    if (_currentOrdersIdentity != _lastOrdersIdentity) {
      _subscribeOrdersAndPayments();
    }
  }

  void _subscribeProducts() {
    _productsSubscription?.cancel();
    final kind = _currentQueryKind;
    _lastQueryKind = kind;

    if (kind == _QueryKind.signedOut) {
      // No protected listener while signed out - firestore.rules denies
      // both the admin and customer queries outright for an unauthenticated
      // caller (every branch requires isSignedIn()), so there is nothing
      // useful to subscribe to. Clear the cache instead of leaving a
      // doomed subscription running.
      _productsSubscription = null;
      _products = [];
      notifyListeners();
      return;
    }

    // Admin: unfiltered - satisfies the rule's isAdmin() branch, gives
    // Admin the full catalog (drafts/inactive included).
    // Customer: the query itself must already imply `published &&
    // isActive` - a collection-wide list query without this filter is
    // denied outright by firestore.rules for a non-admin caller.
    final Query<Map<String, dynamic>> query = kind == _QueryKind.admin
        ? _productsCollection
        : _productsCollection
              .where('publicationStatus', isEqualTo: 'published')
              .where('isActive', isEqualTo: true);

    _productsSubscription = query.snapshots().listen(
      (snapshot) {
        _products = snapshot.docs
            .map((doc) => productModelFromFirestore(doc.id, doc.data()))
            .toList();
        notifyListeners();
      },
      // Defensive: a stream error (e.g. offline) must never crash the app -
      // fall back to an empty list so Home/Explore/Product Details show
      // their existing empty/error states instead.
      onError: (_) {
        _products = [];
        notifyListeners();
      },
    );
  }

  /// Phase 8.9. Re-subscribes both `orders` and `payments` together,
  /// scoped by [_OrdersIdentity] (role AND uid - see that class's doc
  /// comment). Any identity change - including a direct uid change with the
  /// role unchanged - synchronously clears both caches before starting the
  /// new subscription(s), so a stale cross-account frame is never visible.
  void _subscribeOrdersAndPayments() {
    _ordersSubscription?.cancel();
    _paymentsSubscription?.cancel();
    final identity = _currentOrdersIdentity;
    _lastOrdersIdentity = identity;
    final generation = ++_ordersGeneration;

    // Any identity change (including signedOut) clears synchronously first -
    // never leaves a previous identity's data visible during the gap before
    // a new subscription's first snapshot arrives.
    _orders = [];
    _payments = [];
    hasOrdersError = false;
    hasPaymentsError = false;

    if (identity.kind == _QueryKind.signedOut) {
      _ordersSubscription = null;
      _paymentsSubscription = null;
      notifyListeners();
      return;
    }

    final bool isAdmin = identity.kind == _QueryKind.admin;
    final Query<Map<String, dynamic>> ordersQuery = isAdmin
        ? _ordersCollection
        : _ordersCollection.where('userId', isEqualTo: identity.uid);
    final Query<Map<String, dynamic>> paymentsQuery = isAdmin
        ? _paymentsCollection
        : _paymentsCollection.where('userId', isEqualTo: identity.uid);

    _ordersSubscription = ordersQuery.snapshots().listen(
      (snapshot) => _onOrdersSnapshot(
        generation,
        snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())).toList(),
      ),
      onError: (_) => _onOrdersError(generation),
    );
    _paymentsSubscription = paymentsQuery.snapshots().listen(
      (snapshot) => _onPaymentsSnapshot(
        generation,
        snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())).toList(),
      ),
      onError: (_) => _onPaymentsError(generation),
    );
    notifyListeners();
  }

  bool _isStale(int generation) => generation != _ordersGeneration;

  /// Takes plain `(docId, data)` pairs rather than a real
  /// `QuerySnapshot` so this handler - and therefore the generation-guard/
  /// error-preservation/malformed-document behavior it implements - can be
  /// exercised deterministically from a test via [debugSimulateOrdersSnapshot]
  /// without depending on `FakeFirebaseFirestore`'s actual stream timing
  /// (mirrors `FirestoreCategoryRepository`'s established `_onSnapshot`
  /// pattern from the Phase 8.8 hardening pass).
  void _onOrdersSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    if (_isStale(generation)) return;
    try {
      _orders = docs
          .map((e) => orderModelFromFirestore(e.key, e.value))
          .toList();
      hasOrdersError = false;
      notifyListeners();
    } catch (_) {
      // A structurally malformed document must never crash the listener -
      // and per the Phase 8.9 correction, must not silently replace a
      // customer's real order history with an indistinguishable empty
      // state either. Keep whatever was last successfully loaded.
      hasOrdersError = true;
      notifyListeners();
    }
  }

  void _onOrdersError(int generation) {
    if (_isStale(generation)) return;
    // Transient listener error (e.g. offline): preserve the last
    // successfully-loaded cache for the CURRENT identity rather than
    // clearing to empty - an empty list is indistinguishable from "you
    // have no orders", which would be actively misleading here. The
    // generation guard above already ensures this can never resurrect a
    // PREVIOUS identity's data (that was already cleared synchronously in
    // _subscribeOrdersAndPayments before this subscription even started).
    hasOrdersError = true;
    notifyListeners();
  }

  void _onPaymentsSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    if (_isStale(generation)) return;
    try {
      _payments = docs
          .map((e) => paymentRecordFromFirestore(e.key, e.value))
          .toList();
      hasPaymentsError = false;
      notifyListeners();
    } catch (_) {
      hasPaymentsError = true;
      notifyListeners();
    }
  }

  void _onPaymentsError(int generation) {
    if (_isStale(generation)) return;
    hasPaymentsError = true;
    notifyListeners();
  }

  /// Test-only seam - see `_onOrdersSnapshot`'s doc comment.
  @visibleForTesting
  void debugSimulateOrdersSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) => _onOrdersSnapshot(generation, docs);

  @visibleForTesting
  void debugSimulateOrdersError(int generation) => _onOrdersError(generation);

  @visibleForTesting
  void debugSimulatePaymentsSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) => _onPaymentsSnapshot(generation, docs);

  @visibleForTesting
  void debugSimulatePaymentsError(int generation) =>
      _onPaymentsError(generation);

  /// Test-only seam: the generation a genuinely live orders/payments
  /// subscription would need to match right now to have its event applied.
  @visibleForTesting
  int get debugOrdersGeneration => _ordersGeneration;

  @override
  List<ProductModel> get products => List.unmodifiable(_products);

  @override
  ProductModel getProductById(String id) {
    return _products.firstWhere(
      (p) => p.id == id,
      orElse: () => throw StateError('Product not found: $id'),
    );
  }

  @override
  List<OrderModel> get orders => List.unmodifiable(_orders);
  @override
  List<PaymentRecord> get payments => List.unmodifiable(_payments);

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) =>
      _ordersCollection.doc(orderId).update({'orderStatus': newStatus.name});

  // Phase 8.6: real Firestore product-catalog writes, gated by
  // firestore.rules' `products/{id}` write rule (`isAdmin()` - the ID-token
  // custom claim - only; never the `users/{uid}.role` mirror). The Admin
  // form already reconstructs a complete, valid ProductModel on every save,
  // so add/update both do a full `.set()` from `toFirestoreMap()` - there is
  // no untrusted-client field-shape concern here the way there was for
  // `users/{uid}` (only an admin-claim caller can ever reach this rule
  // branch at all). `updateStock` here is Admin Inventory's product-catalog
  // edit; checkout stock movement is entirely server-side (the
  // `createPaymentIntent` Cloud Function reserves, the webhook / sweep
  // restore), never a client write.
  @override
  Future<void> addProduct(ProductModel product) async {
    final docRef = _productsCollection.doc(product.id);
    // Firestore is a KEYED collection, unlike Mock's plain List (which
    // silently allows two entries with the same id) - a client-generated
    // title-slug id could collide across two independently-created
    // products, and a bare `.set()` would silently overwrite the existing
    // one instead of creating a new product. Guard against that here, for
    // creation only - `updateProduct` is expected to target an existing id
    // and legitimately overwrites it.
    final existing = await docRef.get();
    if (existing.exists) {
      throw StateError(
        'A product with this name already exists. Please use a different name.',
      );
    }
    await docRef.set(product.toFirestoreMap());
  }

  @override
  Future<void> updateProduct(ProductModel product) =>
      _productsCollection.doc(product.id).set(product.toFirestoreMap());

  @override
  Future<void> setProductActive(String productId, bool isActive) =>
      _productsCollection.doc(productId).update({'isActive': isActive});

  // Phase 8.11: Admin Inventory's human-paced manual stock edit. A plain
  // single-document `.update()` (NOT a transaction - a transaction would be
  // unnecessary complexity for a low-frequency, single-writer operation)
  // that also stamps `lastStockUpdatedAt` with a server-resolved timestamp.
  // This is the ONLY client write path that touches `stockQuantity` /
  // `lastStockUpdatedAt`; a full product `.set()` (addProduct/updateProduct)
  // carries an existing value through unchanged via `toFirestoreMap()`.
  // Gated by the unchanged `products/{id}` `allow write: if isAdmin()` rule.
  // Checkout's sale-driven stock movement is 100% server-side (Phase 8.13).
  @override
  Future<void> updateStock(String productId, int newStockQuantity) =>
      _productsCollection.doc(productId).update({
        'stockQuantity': newStockQuantity,
        'lastStockUpdatedAt': FieldValue.serverTimestamp(),
      });

  @override
  Future<void> deleteProduct(String productId) =>
      _productsCollection.doc(productId).delete();

  @override
  void dispose() {
    _authSessionState.removeListener(_onAuthChanged);
    _productsSubscription?.cancel();
    _ordersSubscription?.cancel();
    _paymentsSubscription?.cancel();
    super.dispose();
  }
}
