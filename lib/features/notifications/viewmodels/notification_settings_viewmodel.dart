import 'package:flutter/foundation.dart';

import '../models/notification_prefs.dart';
import '../repositories/notification_settings_repository.dart';
import '../services/notification_lifecycle.dart';
import '../services/notification_permission_service.dart';

/// Backs the Notification Settings screen (customer AND Admin - [isAdmin]
/// selects which categories are shown/written).
///
/// Switches save immediately (optimistic) and roll back with an honest error
/// if the write fails. They gate the PUSH only - the customer inbox always
/// records every event (D7), which the screen says explicitly.
class NotificationSettingsViewModel extends ChangeNotifier {
  NotificationSettingsViewModel({
    required this._repository,
    required this._permission,
    required this._uid,
    required this.isAdmin,
    this._lifecycle,
  });

  final NotificationSettingsRepository _repository;
  final NotificationPermissionService _permission;
  final String? _uid;
  final NotificationLifecycle? _lifecycle;
  final bool isAdmin;

  NotificationPrefs _prefs = const NotificationPrefs();
  NotificationPermissionStatus _permissionStatus =
      NotificationPermissionStatus.denied;
  bool _isLoading = true;
  bool _loadFailed = false;
  bool _isSaving = false;
  String? _saveError;
  bool _disposed = false;

  NotificationPrefs get prefs => _prefs;
  NotificationPermissionStatus get permissionStatus => _permissionStatus;
  bool get isLoading => _isLoading;
  bool get loadFailed => _loadFailed;
  bool get isSaving => _isSaving;

  /// Set when the last save failed; cleared on the next attempt.
  String? get saveError => _saveError;

  bool get permissionGranted =>
      _permissionStatus == NotificationPermissionStatus.granted;

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  Future<void> load() async {
    _isLoading = true;
    _loadFailed = false;
    _notify();
    try {
      _permissionStatus = await _permission.status();
      final uid = _uid;
      if (uid != null) _prefs = await _repository.load(uid);
    } catch (_) {
      _loadFailed = true;
    }
    _isLoading = false;
    _notify();
  }

  Future<void> setPushOrders(bool v) => _update(_prefs.copyWith(pushOrders: v));
  Future<void> setPushReviews(bool v) =>
      _update(_prefs.copyWith(pushReviews: v));
  Future<void> setPushAdminOrders(bool v) =>
      _update(_prefs.copyWith(pushAdminOrders: v));
  Future<void> setPushAdminStock(bool v) =>
      _update(_prefs.copyWith(pushAdminStock: v));
  Future<void> setPushAdminModeration(bool v) =>
      _update(_prefs.copyWith(pushAdminModeration: v));
  Future<void> setPushAdminPayments(bool v) =>
      _update(_prefs.copyWith(pushAdminPayments: v));

  Future<void> _update(NotificationPrefs next) async {
    final uid = _uid;
    if (uid == null || next == _prefs) return;
    final previous = _prefs;
    _prefs = next; // optimistic
    _isSaving = true;
    _saveError = null;
    _notify();
    try {
      await _repository.save(uid, next, isAdmin: isAdmin);
    } catch (_) {
      _prefs = previous;
      _saveError =
          "Couldn't save your notification settings. Please try again.";
    }
    _isSaving = false;
    _notify();
  }

  /// "Turn on" / "Open settings" for the OS permission.
  Future<void> turnOnNotifications() async {
    final lifecycle = _lifecycle;
    if (lifecycle != null) {
      _permissionStatus = await lifecycle.requestFromSettings(admin: isAdmin);
    } else if (_permissionStatus == NotificationPermissionStatus.blocked) {
      await _permission.openSettings();
    } else {
      _permissionStatus = await _permission.request();
    }
    _notify();
  }

  /// Re-reads the OS permission (the user may have changed it in system
  /// settings and come back).
  Future<void> refreshPermission() async {
    _permissionStatus = await _permission.status();
    _notify();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
