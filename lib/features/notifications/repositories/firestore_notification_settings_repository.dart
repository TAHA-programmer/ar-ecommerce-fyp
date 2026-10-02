import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/notification_prefs.dart';
import 'notification_settings_repository.dart';

/// Firestore [NotificationSettingsRepository]. The write shape is exactly what
/// the `isValidNotificationPrefs` rule accepts: only the role's push keys
/// (booleans) plus `updatedAt == request.time` - a customer never sends a
/// `pushAdmin*` key (the whole write would be denied).
class FirestoreNotificationSettingsRepository
    implements NotificationSettingsRepository {
  FirestoreNotificationSettingsRepository({FirebaseFirestore? firestore})
    : _injected = firestore;

  final FirebaseFirestore? _injected;

  FirebaseFirestore get _firestore => _injected ?? FirebaseFirestore.instance;

  DocumentReference<Map<String, dynamic>> _doc(String uid) => _firestore
      .collection('users')
      .doc(uid)
      .collection('notificationSettings')
      .doc('prefs');

  @override
  Future<NotificationPrefs> load(String uid) async {
    final snap = await _doc(uid).get();
    return NotificationPrefs.fromMap(snap.data());
  }

  @override
  Future<void> save(
    String uid,
    NotificationPrefs prefs, {
    required bool isAdmin,
  }) {
    return _doc(uid).set({
      ...prefs.toMap(isAdmin: isAdmin),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
