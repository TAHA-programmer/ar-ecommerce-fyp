import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../app/viewmodels/auth_session_state.dart';
import '../../features/address/models/address_model.dart';
import 'address_firestore_mapper.dart';
import 'address_repository.dart';

/// Internal-only signal used by [FirestoreAddressRepository.deleteAddress]
/// to force a retry with a FRESH candidate query when the pre-checked
/// replacement candidate turns out to have vanished by the time the
/// transaction actually reads it - never surfaced to callers.
class _CandidateGoneException implements Exception {}

/// Firestore-backed [AddressRepository] (Phase 8.10, hardened in a
/// pre-deployment correction pass after independent review).
///
/// **Owner-scoped, uid-keyed subscriptions.** Unlike `FirestoreCategoryRepository`
/// (role-aware), this class is scoped by `uid` alone - every signed-in user
/// only ever has access to their own `users/{uid}/addresses` subcollection
/// (enforced by `firestore.rules`' `isOwner(uid)`), so there is no
/// "admin sees everything" branch to track. Re-subscribes on ANY uid change
/// - including a direct Customer A -> Customer B switch - via [_generation]
/// (publicly exposed as [generation] so callers like `CustomerAddressState`
/// can detect "the active uid changed while my write was in flight" without
/// depending on live-cache/listener timing), mirroring
/// `FirestoreCommerceDatabase`'s Phase 8.9 `_OrdersIdentity` pattern:
/// `StreamSubscription.cancel()` is asynchronous and cannot guarantee an
/// in-flight event from a superseded uid's listener is discarded before the
/// new uid's listener starts receiving events, so every snapshot/error
/// callback re-checks its captured generation before ever touching a shared
/// field. [_subscribe] also clears the cache SYNCHRONOUSLY before starting
/// the new subscription(s), so User A's addresses are never visible for
/// even one frame while User B's data is still loading.
///
/// **Two independent subscriptions, tracked independently.** `addresses`
/// (the collection) and `addressDefault/pointer` (the single default
/// pointer doc) are two separate Firestore listeners. [isLoading] only
/// clears once BOTH have delivered their first snapshot for the current
/// generation - a pre-deployment correction: the original implementation
/// cleared `isLoading` the instant EITHER listener fired first, which could
/// report "loaded" while the other subscription's data (e.g. which address
/// is actually default) hadn't arrived yet.
///
/// **Authoritative default-address pointer.** The original plan's
/// "query the current default, then transact" approach cannot actually
/// guarantee a single default: two devices could both read the same old
/// default, then each independently (and validly, by that flawed design)
/// mark a DIFFERENT address as the new default, leaving two documents both
/// claiming `isDefault: true` with no shared arbiter. This implementation
/// corrects that by never storing `isDefault` as a real field on an address
/// document at all - see `address_firestore_mapper.dart`'s header comment.
/// Instead, a single `users/{uid}/addressDefault/pointer` document holds
/// `{ defaultAddressId, updatedAt }`, and [AddressModel.isDefault] is always
/// DERIVED (`address.id == pointer.defaultAddressId`) when addresses are
/// mapped for display. [addAddress]/[updateAddress] accept a `makeDefault`
/// flag applied ATOMICALLY in the SAME write as the create/update (a
/// pre-deployment correction: promoting a brand-new address to default used
/// to require a separate follow-up `setDefaultAddress` call keyed off the
/// caller's local cache, which could race or silently target a stale
/// selection - see `CustomerAddressState`'s doc comment for the bug this
/// closes). [deleteAddress]'s default-reassignment case is hardened against
/// two further races found by independent review - see that method's doc
/// comment.
class FirestoreAddressRepository extends AddressRepository {
  final AuthSessionState _authSessionState;
  final FirebaseFirestore _firestore;

  List<MapEntry<String, Map<String, dynamic>>> _rawDocs = [];
  String? _defaultId;
  bool _addressesLoaded = false;
  bool _pointerLoaded = false;
  bool _hasError = false;

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
  _addressesSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
  _pointerSubscription;
  String? _lastUid;

  /// See the class doc comment's uid-isolation section and [generation].
  int _generation = 0;

  FirestoreAddressRepository(
    this._authSessionState, {
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _authSessionState.addListener(_onAuthChanged);
    _subscribe();
  }

  CollectionReference<Map<String, dynamic>> _addressesCollection(String uid) =>
      _firestore.collection('users').doc(uid).collection('addresses');

  /// Single well-known document per uid - the authoritative default-address
  /// pointer. See the class doc comment. The document ID is always the
  /// literal `'pointer'` - `firestore.rules`' `addressDefault/pointer` match
  /// block only accepts writes to that exact path, never any other document
  /// ID under this subcollection (a pre-deployment hardening: the original
  /// rule used an unconstrained `{pointerId}` wildcard).
  DocumentReference<Map<String, dynamic>> _pointerRef(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('addressDefault')
      .doc('pointer');

  String? get _currentUid =>
      _authSessionState.isAuthenticated ? _authSessionState.userId : null;

  void _onAuthChanged() {
    if (_currentUid == _lastUid) return;
    _subscribe();
  }

  void _subscribe() {
    _addressesSubscription?.cancel();
    _pointerSubscription?.cancel();
    final uid = _currentUid;
    _lastUid = uid;
    final generation = ++_generation;

    // Clear synchronously BEFORE the new subscription's first snapshot can
    // possibly arrive - a direct uid change must never leave the previous
    // user's addresses/default visible on screen while the new listener is
    // still spinning up.
    _rawDocs = [];
    _defaultId = null;
    _hasError = false;

    if (uid == null) {
      _addressesSubscription = null;
      _pointerSubscription = null;
      _addressesLoaded = true;
      _pointerLoaded = true;
      notifyListeners();
      return;
    }

    _addressesLoaded = false;
    _pointerLoaded = false;
    notifyListeners();

    _addressesSubscription = _addressesCollection(uid).snapshots().listen(
      (snapshot) => _onAddressesSnapshot(
        generation,
        snapshot.docs.map((d) => MapEntry(d.id, d.data())).toList(),
      ),
      onError: (_) => _onError(generation),
    );
    _pointerSubscription = _pointerRef(uid).snapshots().listen(
      (snapshot) => _onPointerSnapshot(generation, snapshot.data()),
      onError: (_) => _onError(generation),
    );
  }

  bool _isStale(int generation) => generation != _generation;

  void _onAddressesSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    if (_isStale(generation)) return;
    // Mapping is deferred to the `addresses` getter (combined with
    // `_defaultId`) - `address_firestore_mapper.dart`'s field-level `is T`
    // checks never throw, so no malformed document can crash this handler.
    _rawDocs = docs;
    _addressesLoaded = true;
    _hasError = false;
    notifyListeners();
  }

  void _onPointerSnapshot(int generation, Map<String, dynamic>? data) {
    if (_isStale(generation)) return;
    // Defensive `is String` check (never an unsafe `as String?` cast) - a
    // pre-deployment correction: a present-but-wrong-typed field used to
    // throw a TypeError inside this callback, crashing the listener. Every
    // other Phase 8.10 mapper already follows this convention; this was the
    // one spot that didn't.
    final raw = data?['defaultAddressId'];
    _defaultId = raw is String ? raw : null;
    _pointerLoaded = true;
    _hasError = false;
    notifyListeners();
  }

  /// A transient listener error (e.g. offline) for the CURRENT uid preserves
  /// whatever was last successfully loaded rather than clearing to an
  /// indistinguishable-from-empty state - mirrors
  /// `FirestoreCommerceDatabase`'s Phase 8.9 orders/payments convention. The
  /// generation guard above already ensures this can never resurrect a
  /// PREVIOUS uid's data (that was cleared synchronously in [_subscribe]
  /// before this subscription even started).
  void _onError(int generation) {
    if (_isStale(generation)) return;
    _hasError = true;
    _addressesLoaded = true;
    _pointerLoaded = true;
    notifyListeners();
  }

  /// Test-only seam - mirrors `FirestoreCategoryRepository.debugSimulateSnapshot`.
  @visibleForTesting
  void debugSimulateAddressesSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) => _onAddressesSnapshot(generation, docs);

  @visibleForTesting
  void debugSimulatePointerSnapshot(
    int generation,
    Map<String, dynamic>? data,
  ) => _onPointerSnapshot(generation, data);

  @visibleForTesting
  void debugSimulateError(int generation) => _onError(generation);

  @visibleForTesting
  int get debugGeneration => _generation;

  @override
  int get generation => _generation;

  @override
  bool get isLoading => !(_addressesLoaded && _pointerLoaded);

  @override
  bool get hasError => _hasError;

  @override
  List<AddressModel> get addresses {
    final mapped = _rawDocs
        .map((e) => addressModelFromFirestore(e.key, e.value, _defaultId))
        .toList();
    // createdAt with a document-ID tie-break - see the abstract getter's
    // doc comment for why Dart's `List.sort` alone isn't deterministic
    // enough on a tie.
    mapped.sort((a, b) {
      final byDate = a.createdAt.compareTo(b.createdAt);
      return byDate != 0 ? byDate : a.id.compareTo(b.id);
    });
    return List.unmodifiable(mapped);
  }

  /// See the class doc comment. `becameDefault` is decided INSIDE the
  /// transaction (the pointer is read there, not from the local cache), so
  /// this is correct even under concurrent first-address creation from two
  /// devices: whichever transaction commits first claims the default: the
  /// other's read of the pointer is invalidated by Firestore's commit
  /// protocol and is retried, at which point it observes the now-set
  /// pointer and correctly does NOT also claim default (unless it also
  /// explicitly passed `makeDefault: true`, in which case it still wins the
  /// LAST-committed default, which is the expected "explicit request always
  /// wins" semantics for a non-first address).
  @override
  Future<AddressModel> addAddress(
    AddressDraft draft, {
    bool makeDefault = false,
  }) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');

    final docRef = _addressesCollection(uid).doc();
    final pointerRef = _pointerRef(uid);
    bool becameDefault = false;

    await _firestore.runTransaction((transaction) async {
      final pointerSnap = await transaction.get(pointerRef);
      final currentDefaultId = pointerSnap.data()?['defaultAddressId'];
      final hasRealDefault = currentDefaultId is String;
      becameDefault = makeDefault || !hasRealDefault;

      transaction.set(docRef, draft.toFirestoreCreateMap());
      if (becameDefault) {
        transaction.set(pointerRef, {
          'defaultAddressId': docRef.id,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      }
    });

    // Display-only approximation of `createdAt` for the immediate return
    // value (the real server timestamp arrives moments later via the live
    // listener and idempotently reconciles) - `isDefault`, unlike
    // `createdAt`, is NOT an approximation: it is exactly what the
    // transaction above just committed, so callers can trust and act on it
    // immediately without waiting for any listener event.
    return AddressModel(
      id: docRef.id,
      label: draft.label,
      fullName: draft.fullName,
      phoneNumber: draft.phoneNumber,
      addressLine1: draft.addressLine1,
      addressLine2: draft.addressLine2,
      city: draft.city,
      provinceOrState: draft.provinceOrState,
      postalCode: draft.postalCode,
      isDefault: becameDefault,
      createdAt: DateTime.now(),
    );
  }

  @override
  Future<void> updateAddress(
    AddressModel address, {
    bool makeDefault = false,
  }) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');
    final addressRef = _addressesCollection(uid).doc(address.id);

    if (!makeDefault) {
      await addressRef.update(address.toFirestoreUpdateMap());
      return;
    }

    // Field update + default-pointer claim committed as ONE atomic unit -
    // a `WriteBatch` (not a transaction) is sufficient and cheaper here
    // since neither write is conditioned on a prior read.
    final pointerRef = _pointerRef(uid);
    final batch = _firestore.batch();
    batch.update(addressRef, address.toFirestoreUpdateMap());
    batch.set(pointerRef, {
      'defaultAddressId': address.id,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await batch.commit();
  }

  @override
  Future<void> setDefaultAddress(String addressId) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');

    final addressRef = _addressesCollection(uid).doc(addressId);
    final pointerRef = _pointerRef(uid);

    await _firestore.runTransaction((transaction) async {
      final addressSnap = await transaction.get(addressRef);
      if (!addressSnap.exists) {
        throw StateError('Address not found: $addressId');
      }
      transaction.set(pointerRef, {
        'defaultAddressId': addressId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Deletes [addressId]. If it was the default, the earliest remaining
  /// address (by `createdAt`, document-ID tie-break) becomes the new
  /// default.
  ///
  /// Firestore transactions can only `get()` a [DocumentReference], never
  /// run a `Query` - so the replacement CANDIDATE is found by a plain query
  /// OUTSIDE the transaction, then RE-VALIDATED (a real document `get()`)
  /// INSIDE it before ever being trusted.
  ///
  /// Two concurrency gaps found by independent review, both closed here:
  ///
  /// 1. **The pre-checked candidate vanishes before the transaction reads
  ///    it** (a concurrent device deleted it too). The original
  ///    implementation silently committed `defaultAddressId: null` in this
  ///    case - wrong, since a DIFFERENT valid candidate might still exist.
  ///    Fixed: the transaction now throws [_CandidateGoneException] instead
  ///    of committing, which forces the outer loop to retry with a FRESH
  ///    candidate query - bounded to [_maxDeleteAttempts], surfacing a
  ///    clean [StateError] if it genuinely can't converge in that many
  ///    tries (which would only happen under sustained, unrealistic
  ///    concurrent churn).
  /// 2. **No candidate exists at outer-query time, but a concurrent device
  ///    adds a new address before this transaction commits.** Example:
  ///    Alice has exactly one address (the default). Device A starts
  ///    deleting it - the outer query (correctly) finds no candidate.
  ///    Device B's `addAddress` then runs and commits FIRST: its own
  ///    transaction reads the pointer, sees the old default still set (not
  ///    null yet, since A hasn't committed), so B's new address is created
  ///    as non-default - entirely correct given what B could see at that
  ///    moment. Device A's transaction then commits, deleting the old
  ///    default and setting the pointer to `null` (per its stale,
  ///    already-gathered "no candidate" state) - now B's address exists but
  ///    nothing is marked default. Neither transaction did anything wrong
  ///    in isolation; the gap is structural (a transaction can't know about
  ///    a document that didn't exist when it started). Fixed: every
  ///    successful delete calls [_reconcileMissingDefault] afterward - an
  ///    idempotent, transactionally-safe "claim a default only if one is
  ///    currently missing and at least one address exists" step that closes
  ///    this specific window without ever overwriting a legitimately-set
  ///    default.
  @override
  Future<void> deleteAddress(String addressId) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('You are not signed in.');

    final addressRef = _addressesCollection(uid).doc(addressId);
    final pointerRef = _pointerRef(uid);

    for (var attempt = 1; attempt <= _maxDeleteAttempts; attempt++) {
      final earliestTwo = await _addressesCollection(
        uid,
      ).orderBy('createdAt').limit(2).get();
      final candidateId = earliestTwo.docs
          .map((d) => d.id)
          .firstWhere((id) => id != addressId, orElse: () => '');

      try {
        await _firestore.runTransaction((transaction) async {
          final addressSnap = await transaction.get(addressRef);
          if (!addressSnap.exists) {
            // Already deleted by a concurrent call - nothing left to do.
            return;
          }
          final pointerSnap = await transaction.get(pointerRef);
          final currentDefaultId = pointerSnap.data()?['defaultAddressId'];
          final wasDefault =
              currentDefaultId is String && currentDefaultId == addressId;

          if (wasDefault && candidateId.isNotEmpty) {
            final candidateSnap = await transaction.get(
              _addressesCollection(uid).doc(candidateId),
            );
            if (!candidateSnap.exists) {
              // The candidate this attempt planned to use is gone - force a
              // full retry with a fresh query rather than falling back to
              // null while a different valid candidate might exist.
              throw _CandidateGoneException();
            }
          }

          transaction.delete(addressRef);
          if (wasDefault) {
            transaction.set(pointerRef, {
              'defaultAddressId': candidateId.isNotEmpty ? candidateId : null,
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        });

        // Safety net for gap #2 above - a no-op unless the pointer is
        // currently missing AND at least one address still exists.
        await _reconcileMissingDefault(uid);
        return;
      } on _CandidateGoneException {
        if (attempt == _maxDeleteAttempts) {
          throw StateError(
            'Could not delete this address right now - please try again.',
          );
        }
        continue;
      } on FirebaseException {
        if (attempt == _maxDeleteAttempts) rethrow;
      }
    }
  }

  /// Idempotent, transaction-safe reconciliation: claims a default ONLY
  /// when the pointer is currently missing (`null`/absent) AND at least one
  /// address exists - never overwrites an already-set default, so it can
  /// never race or clobber a concurrent legitimate [setDefaultAddress]/
  /// [addAddress] call. Safe to call unconditionally after [deleteAddress];
  /// a `FirebaseException` here is treated as best-effort (swallowed) since
  /// the caller's own delete already succeeded - the next add/delete/
  /// setDefault naturally re-attempts reconciliation if this one couldn't
  /// complete.
  Future<void> _reconcileMissingDefault(String uid) async {
    final snap = await _addressesCollection(
      uid,
    ).orderBy('createdAt').limit(1).get();
    if (snap.docs.isEmpty) return;
    final candidateId = snap.docs.first.id;
    final pointerRef = _pointerRef(uid);

    try {
      await _firestore.runTransaction((transaction) async {
        final pointerSnap = await transaction.get(pointerRef);
        final currentDefaultId = pointerSnap.data()?['defaultAddressId'];
        if (currentDefaultId is String) return; // already has a default

        final candidateSnap = await transaction.get(
          _addressesCollection(uid).doc(candidateId),
        );
        if (!candidateSnap.exists) return; // vanished again - a future op
        // (the next add/delete/setDefault) will naturally re-attempt this.

        transaction.set(pointerRef, {
          'defaultAddressId': candidateId,
          'updatedAt': FieldValue.serverTimestamp(),
        });
      });
    } on FirebaseException {
      // Best-effort safety net only - see the doc comment above.
    }
  }

  static const int _maxDeleteAttempts = 3;

  @override
  void dispose() {
    _generation++;
    _addressesSubscription?.cancel();
    _pointerSubscription?.cancel();
    _authSessionState.removeListener(_onAuthChanged);
    super.dispose();
  }
}
