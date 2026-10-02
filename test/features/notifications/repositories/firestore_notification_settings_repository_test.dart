import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/features/notifications/models/notification_prefs.dart';
import 'package:twin_ar/features/notifications/repositories/firestore_notification_settings_repository.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late FirestoreNotificationSettingsRepository repo;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    repo = FirestoreNotificationSettingsRepository(firestore: firestore);
  });

  test('a missing doc loads the all-ON defaults', () async {
    expect(await repo.load('alice'), const NotificationPrefs());
  });

  test(
    'a customer save writes ONLY pushOrders/pushReviews + updatedAt',
    () async {
      await repo.save(
        'alice',
        const NotificationPrefs(pushOrders: false),
        isAdmin: false,
      );
      final data =
          (await firestore.doc('users/alice/notificationSettings/prefs').get())
              .data()!;
      expect(data.keys.toSet(), {'pushOrders', 'pushReviews', 'updatedAt'});
      expect(data['pushOrders'], false);
      expect(data['pushReviews'], true);
      expect(data.keys.any((k) => k.startsWith('pushAdmin')), isFalse);
    },
  );

  test('an admin save writes ONLY the four admin keys + updatedAt', () async {
    await repo.save(
      'admin-uid',
      const NotificationPrefs(pushAdminStock: false),
      isAdmin: true,
    );
    final data =
        (await firestore
                .doc('users/admin-uid/notificationSettings/prefs')
                .get())
            .data()!;
    expect(data.keys.toSet(), {
      'pushAdminOrders',
      'pushAdminStock',
      'pushAdminModeration',
      'pushAdminPayments',
      'updatedAt',
    });
    expect(data['pushAdminStock'], false);
  });

  test('round-trips what was saved', () async {
    await repo.save(
      'alice',
      const NotificationPrefs(pushOrders: false, pushReviews: false),
      isAdmin: false,
    );
    final loaded = await repo.load('alice');
    expect(loaded.pushOrders, isFalse);
    expect(loaded.pushReviews, isFalse);
  });

  test('saving for one user never touches another user', () async {
    await repo.save(
      'alice',
      const NotificationPrefs(pushOrders: false),
      isAdmin: false,
    );
    expect(await repo.load('bob'), const NotificationPrefs());
  });
}
