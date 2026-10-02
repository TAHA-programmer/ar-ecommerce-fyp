import 'dart:async';

import 'package:flutter/foundation.dart';

import '../notification_constants.dart';
import 'device_registration_backend.dart';
import 'device_registration_store.dart';
import 'fcm_token_source.dart';
import 'notification_permission_service.dart';

/// Result of a registration attempt. Never an exception: the notification
/// layer is best-effort and must never break sign-in, sign-out or the app.
enum DeviceRegistrationOutcome {
  /// The server accepted the (new or refreshed) token.
  registered,

  /// This exact token was already registered for this user recently.
  upToDate,

  /// OS notification permission is not granted - nothing was registered
  /// (a token that can never display would only add server clutter).
  skippedNoPermission,

  /// FCM returned no token (no Play services / offline).
  noToken,

  /// The callable failed (offline, undeployed, server error). Retried on a
  /// later launch/login.
  failed,
}

/// FCM device-token lifecycle (plan §4.7): register / refresh / unregister
/// for the signed-in user. Pure orchestration over four injected seams
/// ([FcmTokenSource], [DeviceRegistrationBackend],
/// [NotificationPermissionService], [DeviceRegistrationStore]) so every
/// branch is unit-testable with fakes.
///
/// Stage S4 delivers this service and its tests only. It is NOT started
/// anywhere yet: Stage S5 attaches it to `AuthSessionState` (sign-in sync),
/// calls [unregisterCurrentDevice] BEFORE `signOut()` in both logout paths,
/// and asks for the OS permission at a contextual opt-in moment.
///
/// Operations are serialized (a login sync and a token-refresh sync can never
/// interleave with a logout unregister).
class DeviceRegistrationService {
  DeviceRegistrationService({
    required this._tokens,
    required this._backend,
    required this._permission,
    DeviceRegistrationStore? store,
    DateTime Function()? clock,
    this._appVersion = NotificationConstants.appVersion,
  }) : _store = store ?? DeviceRegistrationStore(),
       _clock = clock ?? DateTime.now;

  final FcmTokenSource _tokens;
  final DeviceRegistrationBackend _backend;
  final NotificationPermissionService _permission;
  final DeviceRegistrationStore _store;
  final DateTime Function() _clock;
  final String _appVersion;

  Future<void> _tail = Future<void>.value();
  StreamSubscription<String>? _refreshSub;

  Future<T> _serialized<T>(Future<T> Function() op) {
    final result = _tail.then((_) => op());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }

  /// Registers (or refreshes) this device for [uid] when permitted and
  /// needed. [force] skips the "already up to date" shortcut.
  Future<DeviceRegistrationOutcome> sync(String uid, {bool force = false}) {
    return _serialized(() => _sync(uid, force: force, knownToken: null));
  }

  Future<DeviceRegistrationOutcome> _sync(
    String uid, {
    required bool force,
    required String? knownToken,
  }) async {
    try {
      if (await _permission.status() != NotificationPermissionStatus.granted) {
        return DeviceRegistrationOutcome.skippedNoPermission;
      }
      final token = knownToken ?? await _tokens.getToken();
      if (token == null || token.isEmpty) {
        return DeviceRegistrationOutcome.noToken;
      }

      final nowMs = _clock().millisecondsSinceEpoch;
      final last = await _store.lastRegistered();
      if (!force &&
          last != null &&
          last.uid == uid &&
          last.token == token &&
          nowMs - last.registeredAtMs <
              NotificationConstants.reRegisterAfter.inMilliseconds) {
        return DeviceRegistrationOutcome.upToDate;
      }

      final ok = await _backend.register(
        token: token,
        installId: await _store.installId(),
        appVersion: _appVersion,
      );
      if (!ok) return DeviceRegistrationOutcome.failed;

      await _store.saveRegistered(
        RegisteredDevice(uid: uid, token: token, registeredAtMs: nowMs),
      );
      return DeviceRegistrationOutcome.registered;
    } catch (e) {
      debugPrint('DeviceRegistrationService.sync failed: ${e.runtimeType}');
      return DeviceRegistrationOutcome.failed;
    }
  }

  /// Starts re-registering whenever FCM rotates the token, for whichever user
  /// [currentUid] reports at that moment (`null` = signed out -> ignored).
  /// Idempotent: calling it again replaces the previous subscription.
  void watchTokenRefresh(String? Function() currentUid) {
    _refreshSub?.cancel();
    _refreshSub = _tokens.onTokenRefresh.listen((token) {
      final uid = currentUid();
      if (uid == null) return;
      _serialized(() => _sync(uid, force: true, knownToken: token));
    }, onError: (_) {});
  }

  /// Call BEFORE `signOut()` while still authenticated: removes this device's
  /// token doc server-side (best-effort, time-boxed), then deletes the local
  /// FCM token so the previous user can never receive pushes here, then
  /// forgets the stored registration. Returns `true` when nothing needed
  /// doing or the server call succeeded; `false` when the server call failed
  /// (the token is still invalidated locally and the server prunes it on the
  /// next failed send - plan §4.7). Never throws, never hangs.
  Future<bool> unregisterCurrentDevice() {
    return _serialized(() async {
      var serverOk = true;
      try {
        final last = await _store.lastRegistered();
        if (last != null) {
          serverOk = await _backend
              .unregister(token: last.token)
              .timeout(NotificationConstants.unregisterTimeout);
        }
      } catch (e) {
        serverOk = false;
        debugPrint('unregisterCurrentDevice (server) failed: ${e.runtimeType}');
      }
      try {
        await _tokens.deleteToken().timeout(
          NotificationConstants.unregisterTimeout,
        );
      } catch (e) {
        debugPrint('unregisterCurrentDevice (local) failed: ${e.runtimeType}');
      }
      try {
        await _store.clearRegistered();
      } catch (_) {}
      return serverOk;
    });
  }

  Future<void> dispose() async {
    await _refreshSub?.cancel();
    _refreshSub = null;
  }
}
