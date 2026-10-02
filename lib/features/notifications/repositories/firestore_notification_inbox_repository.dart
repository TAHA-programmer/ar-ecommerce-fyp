import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import '../models/app_notification.dart';
import 'notification_inbox_repository.dart';

/// Firestore-backed [NotificationInboxRepository]. Same uid-isolation design
/// as `FirestoreFavoritesRepository`: an owner-scoped live subscription with a
/// monotonic generation guard so a fast logout/login can never surface the
/// previous account's rows. Only a signed-in CUSTOMER subscribes - an admin
/// has no inbox and a signed-out app reads nothing.
///
/// Query = exactly what `firestore.rules` allows and the plan specifies:
/// `orderBy createdAt desc limit 50` under the owner's own path. Writes are
/// limited to `readAt = serverTimestamp()` (mark read) and `delete` - the
/// rules reject everything else.
class FirestoreNotificationInboxRepository extends NotificationInboxRepository {
  FirestoreNotificationInboxRepository(
    this._authSessionState, {
    FirebaseFirestore? firestore,
  }) : _injected = firestore {
    _authSessionState.addListener(_onAuthChanged);
    _subscribe();
  }

  final AuthSessionState _authSessionState;
  final FirebaseFirestore? _injected;

  FirebaseFirestore get _firestore => _injected ?? FirebaseFirestore.instance;

  List<AppNotification> _items = const [];
  bool _isLoading = true;
  bool _hasError = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _subscription;
  String? _lastUid;
  int _generation = 0;

  CollectionReference<Map<String, dynamic>> _collection(String uid) =>
      _firestore.collection('users').doc(uid).collection('notifications');

  String? get _currentUid =>
      _authSessionState.isCustomer ? _authSessionState.userId : null;

  void _onAuthChanged() {
    if (_currentUid == _lastUid) return;
    _subscribe();
  }

  void _subscribe() {
    _subscription?.cancel();
    final uid = _currentUid;
    _lastUid = uid;
    final generation = ++_generation;

    _items = const [];
    _hasError = false;

    if (uid == null) {
      _subscription = null;
      _isLoading = false;
      notifyListeners();
      return;
    }

    _isLoading = true;
    notifyListeners();

    _subscription = _collection(uid)
        .orderBy('createdAt', descending: true)
        .limit(NotificationInboxRepository.windowSize)
        .snapshots()
        .listen(
          (snapshot) => _onSnapshot(
            generation,
            snapshot.docs
                .map((d) => AppNotification.fromFirestore(d.id, d.data()))
                .toList(),
          ),
          onError: (_) => _onError(generation),
        );
  }

  bool _isStale(int generation) => generation != _generation;

  void _onSnapshot(int generation, List<AppNotification> items) {
    if (_isStale(generation)) return;
    _items = List.unmodifiable(items);
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
  void debugSimulateSnapshot(int generation, List<AppNotification> items) =>
      _onSnapshot(generation, items);

  @visibleForTesting
  void debugSimulateError(int generation) => _onError(generation);

  @visibleForTesting
  int get debugGeneration => _generation;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasError => _hasError;

  @override
  List<AppNotification> get notifications => _items;

  @override
  void retry() => _subscribe();

  @override
  Future<bool> markRead(String notificationId) async {
    final uid = _currentUid;
    if (uid == null) return false;
    try {
      await _collection(
        uid,
      ).doc(notificationId).update({'readAt': FieldValue.serverTimestamp()});
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> markAllRead() async {
    final uid = _currentUid;
    if (uid == null) return false;
    final unread = _items.where((n) => n.isUnread).toList();
    if (unread.isEmpty) return true;
    try {
      final batch = _firestore.batch();
      for (final n in unread) {
        batch.update(_collection(uid).doc(n.id), {
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> delete(String notificationId) async {
    final uid = _currentUid;
    if (uid == null) return false;
    try {
      await _collection(uid).doc(notificationId).delete();
      return true;
    } catch (_) {
      return false;
    }
  }

  @override
  void dispose() {
    _authSessionState.removeListener(_onAuthChanged);
    _subscription?.cancel();
    super.dispose();
  }
}
