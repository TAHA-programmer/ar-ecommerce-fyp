import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import '../models/notification_payload.dart';
import 'device_registration_service.dart';
import 'device_registration_store.dart';
import 'fcm_message_source.dart';
import 'notification_navigator.dart';
import 'notification_permission_service.dart';
import 'notification_router.dart';

/// Shows the contextual opt-in sheet; resolves `true` = "Turn on",
/// `false`/`null` = "Not now". Injected so tests need no widget tree.
typedef OptInPresenter = Future<bool?> Function({required bool admin});

/// Shows the foreground banner for a push that arrived while the app is open.
typedef BannerPresenter =
    void Function({
      required String title,
      required String body,
      required VoidCallback onTap,
    });

/// Glue that makes the Stage S4 data layer live (Stage S5): attaches device
/// registration to the auth session, routes notification taps, shows the
/// foreground banner, owns the contextual permission prompts and the
/// unregister-before-signOut step.
///
/// Created lazily by the provider tree and `start()`ed once by
/// `NotificationHost` ONLY in the production app (`TWinArApp
/// (enableNotifications: true)`, set by `main.dart`) - widget tests that pump
/// `TWinArApp` never start it, so they never touch FirebaseMessaging.
class NotificationLifecycle {
  NotificationLifecycle({
    required this._auth,
    required this._registration,
    required this._permission,
    required this._messages,
    required this._navigator,
    required this._presentOptIn,
    required this._presentBanner,
    DeviceRegistrationStore? store,
    this.onNotificationOpened,
  }) : _store = store ?? DeviceRegistrationStore();

  final AuthSessionState _auth;
  final DeviceRegistrationService _registration;
  final NotificationPermissionService _permission;
  final FcmMessageSource _messages;
  final NotificationNavigator _navigator;
  final OptInPresenter _presentOptIn;
  final BannerPresenter _presentBanner;
  final DeviceRegistrationStore _store;

  /// Invoked with the inbox row id when a tapped notification carried one
  /// (best-effort "mark read").
  final void Function(String notificationId)? onNotificationOpened;

  bool _started = false;
  String? _syncedUid;
  StreamSubscription<IncomingPushMessage>? _openedSub;
  StreamSubscription<IncomingPushMessage>? _foregroundSub;

  bool get isStarted => _started;

  /// The identity notifications are validated against.
  NotificationSession get session => NotificationSession(
    uid: _auth.isAuthenticated ? _auth.userId : null,
    isCustomer: _auth.isCustomer,
    isSuperAdmin: _auth.isSuperAdmin,
  );

  /// Idempotent. Never throws (FCM can be unavailable).
  Future<void> start() async {
    if (_started) return;
    _started = true;
    try {
      _auth.addListener(_onAuthChanged);
      _registration.watchTokenRefresh(
        () => _auth.isAuthenticated ? _auth.userId : null,
      );
      _openedSub = _messages.onMessageOpenedApp.listen(
        handleOpened,
        onError: (_) {},
      );
      _foregroundSub = _messages.onForegroundMessage.listen(
        handleForeground,
        onError: (_) {},
      );
      _onAuthChanged();
      final initial = await _messages.initialMessage();
      if (initial != null) handleOpened(initial);
    } catch (e) {
      debugPrint('NotificationLifecycle.start failed: ${e.runtimeType}');
    }
  }

  void _onAuthChanged() {
    final uid = _auth.isAuthenticated ? _auth.userId : null;
    if (uid == null) {
      _syncedUid = null;
    } else if (uid != _syncedUid) {
      _syncedUid = uid;
      // No-op without OS permission (never prompts here - the prompt is
      // always a contextual moment, plan D14).
      unawaited(_registration.sync(uid));
    }
    // A held notification tap may now be resolvable (or droppable).
    _navigator.flush();
  }

  /// A tapped notification (background tap or cold start).
  void handleOpened(IncomingPushMessage message) {
    final payload = NotificationPayload.tryParse(message.data);
    if (payload == null) return;
    _navigator.open(payload);
    final id = payload.notificationId;
    if (id != null) onNotificationOpened?.call(id);
  }

  /// A push that arrived while the app is open: banner only when it is valid
  /// for this session and the user isn't already on its destination.
  void handleForeground(IncomingPushMessage message) {
    final payload = NotificationPayload.tryParse(message.data);
    if (payload == null) return;
    if (NotificationRouter.resolve(payload, session) == null) return;
    if (_navigator.isShowing(payload)) return;
    final title = message.title;
    final body = message.body;
    if (title == null || title.isEmpty) return;
    try {
      _presentBanner(
        title: title,
        body: body ?? '',
        onTap: () => handleOpened(message),
      );
    } catch (e) {
      // UI failure must never break foreground handling (the inbox row and
      // the bell are unaffected); log only the type.
      debugPrint('NotificationLifecycle banner failed: ${e.runtimeType}');
    }
  }

  /// Call BEFORE `signOut()` while still authenticated (both logout paths).
  /// Skipped entirely when the lifecycle was never started (tests).
  Future<void> beforeSignOut() async {
    if (!_started) return;
    _syncedUid = null;
    await _registration.unregisterCurrentDevice();
  }

  /// Contextual opt-in. Returns the resulting OS status, or `null` when
  /// nothing was shown (already granted -> just syncs; already declined and
  /// not [force]d; not signed in).
  Future<NotificationPermissionStatus?> promptOptIn({
    required bool admin,
    bool force = false,
  }) async {
    final uid = _auth.isAuthenticated ? _auth.userId : null;
    if (uid == null) return null;

    final status = await _permission.status();
    if (status == NotificationPermissionStatus.granted) {
      unawaited(_registration.sync(uid));
      return null;
    }
    if (!force && await _store.promptDeclined(admin: admin)) return null;

    final accepted = await _presentOptIn(admin: admin);
    if (accepted != true) {
      await _store.setPromptDeclined(true, admin: admin);
      return null;
    }
    return _requestAndRegister(uid, admin: admin);
  }

  /// The settings screen's "Turn on" action: the user explicitly asked, so the
  /// system dialog is requested directly (a blocked state opens system
  /// settings instead). Returns the resulting status.
  Future<NotificationPermissionStatus> requestFromSettings({
    required bool admin,
  }) async {
    final uid = _auth.isAuthenticated ? _auth.userId : null;
    final status = await _permission.status();
    if (status == NotificationPermissionStatus.granted) {
      if (uid != null) unawaited(_registration.sync(uid));
      return status;
    }
    if (status == NotificationPermissionStatus.blocked) {
      await _permission.openSettings();
      return status;
    }
    if (uid == null) return status;
    return _requestAndRegister(uid, admin: admin);
  }

  Future<NotificationPermissionStatus> _requestAndRegister(
    String uid, {
    required bool admin,
  }) async {
    final result = await _permission.request();
    if (result == NotificationPermissionStatus.granted) {
      await _store.setPromptDeclined(false, admin: admin);
      await _registration.sync(uid, force: true);
    } else {
      await _store.setPromptDeclined(true, admin: admin);
    }
    return result;
  }

  /// After a real order result is shown (customer opt-in moment #1).
  Future<void> maybePromptAfterOrder() async {
    if (!_auth.isCustomer) return;
    await promptOptIn(admin: false);
  }

  /// One-time Admin explainer, when the Admin dashboard is first shown.
  Future<void> maybePromptAdmin() async {
    if (!_auth.isSuperAdmin) return;
    await promptOptIn(admin: true);
  }

  Future<void> dispose() async {
    _auth.removeListener(_onAuthChanged);
    await _openedSub?.cancel();
    await _foregroundSub?.cancel();
    await _registration.dispose();
    _navigator.dispose();
    _started = false;
  }
}
