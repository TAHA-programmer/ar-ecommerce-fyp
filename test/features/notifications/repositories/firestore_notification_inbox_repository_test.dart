import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/notifications/models/app_notification.dart';
import 'package:twin_ar/features/notifications/repositories/firestore_notification_inbox_repository.dart';
import 'package:twin_ar/features/notifications/repositories/notification_inbox_repository.dart';

AuthSessionState _session(String uid, {UserRole role = UserRole.customer}) =>
    AuthSessionState()..setSession(
      AuthResult.success(userId: uid, email: '$uid@x.com', role: role),
    );

Future<void> _until(bool Function() cond, {int ms = 3000}) async {
  final end = DateTime.now().add(Duration(milliseconds: ms));
  while (!cond() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
  if (!cond()) fail('condition not reached in ${ms}ms');
}

Future<void> _seed(
  FakeFirebaseFirestore fs,
  String uid,
  String id, {
  required int createdMs,
  bool read = false,
  String type = 'order_shipped',
}) {
  return fs
      .collection('users')
      .doc(uid)
      .collection('notifications')
      .doc(id)
      .set({
        'type': type,
        'title': 'T $id',
        'body': 'B $id',
        'route': 'orderDetail',
        'entityId': 'ord_$id',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(createdMs),
        'readAt': read
            ? Timestamp.fromMillisecondsSinceEpoch(createdMs + 1)
            : null,
      });
}

void main() {
  late FakeFirebaseFirestore firestore;

  setUp(() => firestore = FakeFirebaseFirestore());

  test(
    'loads the signed-in customer inbox newest first, with unread count',
    () async {
      await _seed(firestore, 'alice', 'old', createdMs: 1000);
      await _seed(firestore, 'alice', 'new', createdMs: 3000);
      await _seed(firestore, 'alice', 'mid', createdMs: 2000, read: true);
      final repo = FirestoreNotificationInboxRepository(
        _session('alice'),
        firestore: firestore,
      );
      addTearDown(repo.dispose);

      await _until(() => !repo.isLoading);
      expect(repo.notifications.map((n) => n.id), ['new', 'mid', 'old']);
      expect(repo.unreadCount, 2);
      expect(repo.hasError, isFalse);
    },
  );

  test(
    'caps the window at 50 rows (the badge can never exceed what is loaded)',
    () async {
      for (var i = 0; i < 55; i++) {
        await _seed(firestore, 'alice', 'n$i', createdMs: 1000 + i);
      }
      final repo = FirestoreNotificationInboxRepository(
        _session('alice'),
        firestore: firestore,
      );
      addTearDown(repo.dispose);
      await _until(() => !repo.isLoading);
      expect(
        repo.notifications,
        hasLength(NotificationInboxRepository.windowSize),
      );
      expect(repo.notifications.first.id, 'n54'); // newest kept
      expect(repo.unreadCount, 50);
    },
  );

  test("never shows another user's rows (uid isolation)", () async {
    await _seed(firestore, 'alice', 'a1', createdMs: 1000);
    await _seed(firestore, 'bob', 'b1', createdMs: 2000);
    final repo = FirestoreNotificationInboxRepository(
      _session('bob'),
      firestore: firestore,
    );
    addTearDown(repo.dispose);
    await _until(() => !repo.isLoading);
    expect(repo.notifications.map((n) => n.id), ['b1']);
  });

  test(
    'an admin session has no inbox: nothing is subscribed or shown',
    () async {
      await _seed(firestore, 'admin-uid', 'x', createdMs: 1000);
      final repo = FirestoreNotificationInboxRepository(
        _session('admin-uid', role: UserRole.superAdmin),
        firestore: firestore,
      );
      addTearDown(repo.dispose);
      await _until(() => !repo.isLoading);
      expect(repo.notifications, isEmpty);
      expect(repo.unreadCount, 0);
      expect(await repo.markRead('x'), isFalse);
      expect(await repo.markAllRead(), isFalse);
      expect(await repo.delete('x'), isFalse);
    },
  );

  test('a signed-out session reads nothing', () async {
    final repo = FirestoreNotificationInboxRepository(
      AuthSessionState(),
      firestore: firestore,
    );
    addTearDown(repo.dispose);
    await _until(() => !repo.isLoading);
    expect(repo.notifications, isEmpty);
  });

  test(
    'logout then login as another user swaps the data and never leaks the old rows',
    () async {
      await _seed(firestore, 'alice', 'a1', createdMs: 1000);
      await _seed(firestore, 'bob', 'b1', createdMs: 2000);
      final auth = _session('alice');
      final repo = FirestoreNotificationInboxRepository(
        auth,
        firestore: firestore,
      );
      addTearDown(repo.dispose);
      await _until(() => repo.notifications.length == 1);
      expect(repo.notifications.single.id, 'a1');

      auth.clearSession();
      await _until(() => repo.notifications.isEmpty && !repo.isLoading);

      auth.setSession(
        AuthResult.success(
          userId: 'bob',
          email: 'b@x.com',
          role: UserRole.customer,
        ),
      );
      await _until(() => repo.notifications.length == 1);
      expect(repo.notifications.single.id, 'b1');
    },
  );

  test('a stale snapshot from a previous user generation is ignored', () async {
    final auth = _session('alice');
    final repo = FirestoreNotificationInboxRepository(
      auth,
      firestore: firestore,
    );
    addTearDown(repo.dispose);
    await _until(() => !repo.isLoading);
    final oldGen = repo.debugGeneration;

    auth.setSession(
      AuthResult.success(
        userId: 'bob',
        email: 'b@x.com',
        role: UserRole.customer,
      ),
    );
    repo.debugSimulateSnapshot(oldGen, [
      AppNotification.fromFirestore('ghost', {'type': 'order_shipped'}),
    ]);
    repo.debugSimulateError(oldGen);
    expect(repo.notifications.where((n) => n.id == 'ghost'), isEmpty);
    expect(repo.hasError, isFalse);
  });

  test(
    'a transient error keeps the last-known list and flags hasError; retry resubscribes',
    () async {
      await _seed(firestore, 'alice', 'a1', createdMs: 1000);
      final repo = FirestoreNotificationInboxRepository(
        _session('alice'),
        firestore: firestore,
      );
      addTearDown(repo.dispose);
      await _until(() => repo.notifications.length == 1);

      repo.debugSimulateError(repo.debugGeneration);
      expect(repo.hasError, isTrue);
      expect(
        repo.notifications,
        hasLength(1),
      ); // never silently "no notifications"

      repo.retry();
      await _until(() => !repo.hasError && repo.notifications.length == 1);
    },
  );

  test('markRead sets readAt on that row only', () async {
    await _seed(firestore, 'alice', 'a1', createdMs: 1000);
    await _seed(firestore, 'alice', 'a2', createdMs: 2000);
    final repo = FirestoreNotificationInboxRepository(
      _session('alice'),
      firestore: firestore,
    );
    addTearDown(repo.dispose);
    await _until(() => repo.notifications.length == 2);

    expect(await repo.markRead('a1'), isTrue);
    await _until(() => repo.unreadCount == 1);
    expect(
      repo.notifications.firstWhere((n) => n.id == 'a1').isUnread,
      isFalse,
    );
    expect(repo.notifications.firstWhere((n) => n.id == 'a2').isUnread, isTrue);
  });

  test('markAllRead clears every unread row in one batch', () async {
    for (var i = 0; i < 4; i++) {
      await _seed(firestore, 'alice', 'n$i', createdMs: 1000 + i, read: i == 0);
    }
    final repo = FirestoreNotificationInboxRepository(
      _session('alice'),
      firestore: firestore,
    );
    addTearDown(repo.dispose);
    await _until(() => repo.notifications.length == 4);
    expect(repo.unreadCount, 3);

    expect(await repo.markAllRead(), isTrue);
    await _until(() => repo.unreadCount == 0);
    expect(await repo.markAllRead(), isTrue); // nothing unread -> still ok
  });

  test('delete removes the row', () async {
    await _seed(firestore, 'alice', 'a1', createdMs: 1000);
    await _seed(firestore, 'alice', 'a2', createdMs: 2000);
    final repo = FirestoreNotificationInboxRepository(
      _session('alice'),
      firestore: firestore,
    );
    addTearDown(repo.dispose);
    await _until(() => repo.notifications.length == 2);

    expect(await repo.delete('a1'), isTrue);
    await _until(() => repo.notifications.length == 1);
    expect(repo.notifications.single.id, 'a2');
  });

  test(
    'writes touch only readAt (mark read) - no other field changes',
    () async {
      await _seed(firestore, 'alice', 'a1', createdMs: 1000);
      final repo = FirestoreNotificationInboxRepository(
        _session('alice'),
        firestore: firestore,
      );
      addTearDown(repo.dispose);
      await _until(() => repo.notifications.length == 1);
      await repo.markRead('a1');
      final doc = await firestore.doc('users/alice/notifications/a1').get();
      final data = doc.data()!;
      expect(data['title'], 'T a1');
      expect(data['body'], 'B a1');
      expect(data['type'], 'order_shipped');
      expect(data['readAt'], isNotNull);
    },
  );
}
