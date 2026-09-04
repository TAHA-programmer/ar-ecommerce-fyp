import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../../app/viewmodels/auth_session_state.dart';
import '../models/category/commerce_category_model.dart';
import '../models/product/product_category.dart';
import 'category_firestore_mapper.dart';
import 'category_repository.dart';

/// Maximum category display-name length, matches `firestore.rules`'
/// `name.size() <= 60` bound.
const int categoryNameMaxLength = 60;

/// Derives the stable, slug-shaped `key`/document-ID from an Admin-entered
/// display name: lowercased, non-alphanumeric runs collapsed to a single
/// `-`, leading/trailing `-` trimmed. Shared by [FirestoreCategoryRepository]
/// and mirrored (independently, since Dart and Node code can't share a
/// function) by `scripts/seed_categories/seed_categories.mjs` - both must
/// stay in sync with `firestore.rules`' `^[a-z0-9-]+$` key-shape validation.
String slugifyCategoryName(String name) {
  final lower = name.trim().toLowerCase();
  final collapsed = lower.replaceAll(RegExp(r'[^a-z0-9]+'), '-');
  return collapsed.replaceAll(RegExp(r'^-+|-+$'), '');
}

/// Shared create-time validation for both [FirestoreCategoryRepository] and
/// [MockCategoryRepository] - a defensive backstop so a direct repository
/// call (bypassing `AdminProductManagementViewModel.addCategory`'s own
/// pre-upload checks) can never create an invalid category. Throws a clean
/// [StateError] (never raw text) on the first violation found - mirrors
/// this project's established "a StateError from the data layer already
/// carries a clean, user-facing message" convention.
///
/// [trimmedName]/[key] must already be [name.trim()]/[slugifyCategoryName]
/// applied by the caller (both repositories need those values for other
/// purposes anyway, so this function doesn't recompute them).
void validateCategoryCreateInput({
  required String trimmedName,
  required String key,
  required ProductCategory kind,
}) {
  if (trimmedName.isEmpty) {
    throw StateError('Please enter a category name.');
  }
  if (trimmedName.length > categoryNameMaxLength) {
    throw StateError(
      'Category name must be $categoryNameMaxLength characters or fewer.',
    );
  }
  if (key.isEmpty) {
    throw StateError('Please enter a valid category name.');
  }
  if (kind == ProductCategory.all) {
    throw StateError('Please choose a specific category type.');
  }
}

/// Same three-way read identity `FirestoreCommerceDatabase` tracks for
/// `products` - see that class's doc comment for why a bare `isSuperAdmin`
/// bool cannot distinguish "signed out" from "signed in as customer".
enum _QueryKind { signedOut, customer, admin }

/// Firestore-backed [CategoryRepository] (Phase 8.8). Mirrors
/// `FirestoreCommerceDatabase`'s exact role-aware re-subscription pattern:
/// Admin gets an unfiltered listener (active + inactive), a signed-in
/// customer gets a `where(isActive==true)` listener (a collection-wide list
/// query without this filter is denied outright by `firestore.rules` for a
/// non-admin caller), and a signed-out session gets no listener at all (the
/// cache is cleared instead of leaving a doomed subscription running).
///
/// Sorting is entirely client-side (`categories`' getter sorts by
/// `sortOrder`) - this catalogue is small (single digits to low tens of
/// categories for an FYP-scope app), so no server-side `orderBy` is used and
/// no composite index is needed, matching the Phase 8.8 plan's explicit
/// query-shape decision.
class FirestoreCategoryRepository extends CategoryRepository {
  final AuthSessionState _authSessionState;
  final FirebaseFirestore _firestore;

  List<CommerceCategoryModel> _categories = [];
  bool _isLoading = true;
  bool _hasError = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  _QueryKind? _lastQueryKind;

  /// Monotonic subscription generation, mirroring `CustomerProfileState`'s
  /// established async-isolation `_generation` pattern (Phase 8.7 Hardening
  /// Pass). `StreamSubscription.cancel()` is asynchronous - it does not
  /// guarantee an event already in flight on the OLD stream (e.g. the
  /// unfiltered Admin query) is discarded before a NEW subscription
  /// (e.g. the customer `isActive`-filtered query) is created. Every
  /// `_subscribe()` call bumps this counter and captures the new value
  /// locally; the snapshot/error callbacks re-check it before touching any
  /// shared field, so a late event from an already-superseded subscription
  /// is silently dropped rather than repopulating stale (possibly
  /// Admin-only/inactive) data into a since-downgraded session.
  int _generation = 0;

  FirestoreCategoryRepository(
    this._authSessionState, {
    FirebaseFirestore? firestore,
  }) : _firestore = firestore ?? FirebaseFirestore.instance {
    _authSessionState.addListener(_onAuthChanged);
    _subscribe();
  }

  CollectionReference<Map<String, dynamic>> get _collection =>
      _firestore.collection('categories');

  _QueryKind get _currentQueryKind {
    if (!_authSessionState.isAuthenticated) return _QueryKind.signedOut;
    return _authSessionState.isSuperAdmin
        ? _QueryKind.admin
        : _QueryKind.customer;
  }

  void _onAuthChanged() {
    if (_currentQueryKind == _lastQueryKind) return;
    // Clear and flip to "loading" synchronously, BEFORE the new
    // subscription's first snapshot can possibly arrive - a direct
    // Admin -> Customer (or vice versa) switch must never leave the
    // previous role's unfiltered/filtered data visible on screen while the
    // new listener is still spinning up.
    _categories = [];
    _isLoading = true;
    _hasError = false;
    notifyListeners();
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    // Bump BEFORE reading `kind`/building the query - this is the single
    // point that invalidates every previously-registered listener closure,
    // regardless of whether `cancel()` above has actually taken effect yet.
    final generation = ++_generation;
    final kind = _currentQueryKind;
    _lastQueryKind = kind;

    if (kind == _QueryKind.signedOut) {
      _subscription = null;
      _categories = [];
      _isLoading = false;
      _hasError = false;
      notifyListeners();
      return;
    }

    final Query<Map<String, dynamic>> query = kind == _QueryKind.admin
        ? _collection
        : _collection.where('isActive', isEqualTo: true);

    _subscription = query.snapshots().listen(
      (snapshot) => _onSnapshot(
        generation,
        snapshot.docs.map((doc) => MapEntry(doc.id, doc.data())).toList(),
      ),
      onError: (_) => _onSnapshotError(generation),
    );
  }

  /// Handles one snapshot event for [generation]. A mismatch against the
  /// live `_generation` means a newer `_subscribe()` call has since
  /// superseded this one (a role/account switch, or dispose) - the event is
  /// silently dropped, never written into any shared field.
  ///
  /// Mapping is wrapped in its own try/catch: malformed Firestore data (a
  /// field with an unexpected type, e.g. `name` stored as a number) would
  /// otherwise throw INSIDE the stream's `onData` callback, which - being
  /// outside any `try`/`catch` the rest of the app controls - would
  /// propagate as an uncaught, app-crashing exception rather than a
  /// recoverable state. A mapping failure surfaces exactly like a stream
  /// `onError` (`hasError = true`), never a crash.
  void _onSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) {
    if (generation != _generation) return;

    final List<CommerceCategoryModel> mapped;
    try {
      mapped = docs
          .map((entry) => categoryModelFromFirestore(entry.key, entry.value))
          .toList();
    } catch (_) {
      _isLoading = false;
      _hasError = true;
      notifyListeners();
      return;
    }

    _categories = mapped;
    _isLoading = false;
    _hasError = false;
    notifyListeners();
  }

  /// Defensive: a stream error (e.g. offline) must never crash the app -
  /// surface a recoverable error state instead (see `hasError`), keeping
  /// whatever was last successfully loaded rather than wiping it. Same
  /// staleness guard as [_onSnapshot].
  void _onSnapshotError(int generation) {
    if (generation != _generation) return;
    _isLoading = false;
    _hasError = true;
    notifyListeners();
  }

  /// Test-only seam: simulates a snapshot event arriving under a specific
  /// [generation] - including a STALE one, deliberately older than the
  /// repository's current live generation - without depending on
  /// `FakeFirebaseFirestore`'s actual `StreamSubscription.cancel()` timing
  /// (which is not guaranteed to be synchronous and must not be relied on
  /// for correctness). This is how the "an old Admin listener's callback
  /// fires after a role switch to Customer" race is proven deterministically
  /// in tests - see `firestore_category_repository_test.dart`.
  @visibleForTesting
  void debugSimulateSnapshot(
    int generation,
    List<MapEntry<String, Map<String, dynamic>>> docs,
  ) => _onSnapshot(generation, docs);

  /// Test-only seam: the generation a genuinely live subscription would need
  /// to match right now to have its event applied.
  @visibleForTesting
  int get debugGeneration => _generation;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasError => _hasError;

  @override
  List<CommerceCategoryModel> get categories {
    final sorted = List<CommerceCategoryModel>.from(_categories);
    sorted.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    return List.unmodifiable(sorted);
  }

  /// Creates a new category via a Firestore transaction: normalizes/trims
  /// [name], derives its stable `key` (== the document ID), transaction-reads
  /// `categories/{key}`, and rejects with a clean [StateError] if it already
  /// exists - only then does the transaction create the document. This is
  /// the AUTHORITATIVE key-uniqueness boundary: two concurrent creates for
  /// the same name can never both succeed, because Firestore aborts and
  /// retries a transaction whose read set changed before it commits.
  ///
  /// Case-insensitive duplicate DISPLAY names (e.g. "Furniture" vs.
  /// "furniture ") are a SEPARATE, application-level check - deliberately
  /// NOT folded into this transaction, because it requires comparing against
  /// every other loaded category's `name`, which is exactly the kind of
  /// broad, non-point read a Firestore transaction is the wrong tool for
  /// (it would need to read the entire collection inside the transaction to
  /// be airtight, which does not scale and is unnecessary for this project's
  /// FYP-scope, single-Admin-at-a-time reality). The ViewModel performs this
  /// check against its already-loaded `categories` list before ever calling
  /// this method; it is a real, documented, Admin-only application boundary,
  /// not a security boundary (nothing prevents two admins from racing this
  /// exact check in true parallel affecting no security guarantee).
  @override
  Future<CommerceCategoryModel> addCategory({
    required String name,
    required ProductCategory kind,
    String imageUrl = '',
    bool isActive = true,
  }) async {
    final trimmedName = name.trim();
    final key = slugifyCategoryName(trimmedName);
    validateCategoryCreateInput(trimmedName: trimmedName, key: key, kind: kind);

    final maxSortOrder = _categories.isEmpty
        ? 0
        : _categories.map((c) => c.sortOrder).reduce((a, b) => a > b ? a : b);
    final sortOrder = maxSortOrder + 10;

    final model = CommerceCategoryModel(
      categoryId: key,
      name: trimmedName,
      key: key,
      kind: kind,
      imageUrl: imageUrl,
      isActive: isActive,
      sortOrder: sortOrder,
    );

    final docRef = _collection.doc(key);
    await _firestore.runTransaction((transaction) async {
      final existing = await transaction.get(docRef);
      if (existing.exists) {
        throw StateError(
          'A category with this name already exists. Please use a different name.',
        );
      }
      transaction.set(docRef, model.toFirestoreMap());
    });

    return model;
  }

  @override
  Future<void> updateCategory(CommerceCategoryModel updated) {
    return _collection.doc(updated.categoryId).update({
      'name': updated.name,
      'imageUrl': updated.imageUrl,
      'isActive': updated.isActive,
      'sortOrder': updated.sortOrder,
    });
  }

  @override
  Future<void> deleteCategory(String categoryId) async {
    if (CommerceCategoryModel.seededCategoryIds.contains(categoryId)) {
      throw StateError('This category cannot be deleted.');
    }
    // Authoritative, live check - independent of whatever the caller's own
    // local product cache currently shows (which may be stale/lagging a
    // very recent product creation). This is the real safety boundary for
    // Phase 8.8b's categoryId reference; AdminProductManagementViewModel's
    // own productCount-based UI guard is a fast convenience only, not to be
    // trusted as the last word.
    final referencing = await _firestore
        .collection('products')
        .where('categoryId', isEqualTo: categoryId)
        .limit(1)
        .get();
    if (referencing.docs.isNotEmpty) {
      throw StateError(
        'This category cannot be deleted because it still has products '
        'assigned to it.',
      );
    }
    await _collection.doc(categoryId).delete();
  }

  @override
  void dispose() {
    // Invalidate any in-flight callback before cancelling - belt-and-
    // suspenders alongside the cancel() call itself, matching
    // `CustomerProfileState._clear()`'s established convention of bumping
    // the generation on teardown, not just on a live role switch.
    _generation++;
    _subscription?.cancel();
    _authSessionState.removeListener(_onAuthChanged);
    super.dispose();
  }
}
