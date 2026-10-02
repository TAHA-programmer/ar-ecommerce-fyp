import '../models/notification_prefs.dart';
import 'notification_settings_repository.dart';

/// In-memory [NotificationSettingsRepository] for tests.
class MockNotificationSettingsRepository
    implements NotificationSettingsRepository {
  MockNotificationSettingsRepository({
    this.stored = const NotificationPrefs(),
    this.failLoad = false,
    this.failSave = false,
  });

  NotificationPrefs stored;
  bool failLoad;
  bool failSave;

  final List<({String uid, NotificationPrefs prefs, bool isAdmin})> saves = [];

  @override
  Future<NotificationPrefs> load(String uid) async {
    if (failLoad) throw StateError('load failed');
    return stored;
  }

  @override
  Future<void> save(
    String uid,
    NotificationPrefs prefs, {
    required bool isAdmin,
  }) async {
    if (failSave) throw StateError('save failed');
    saves.add((uid: uid, prefs: prefs, isAdmin: isAdmin));
    stored = prefs;
  }
}
