import 'package:flutter/widgets.dart';

import '../../../app/routes/route_names.dart';
import '../models/notification_payload.dart';
import 'notification_route_tracker.dart';
import 'notification_router.dart';

/// Opens a tapped notification's destination safely (plan §4.6).
///
/// The tap can arrive while the app is still on Splash/Login (cold start from
/// a notification) or before auth has resolved, so the payload is HELD and
/// only consumed once the Navigator is on a real screen. At that moment it is
/// re-validated against the CURRENT session (a notification for the previous
/// account is dropped, an admin destination needs a superAdmin) and pushed ON
/// TOP of the current stack - never replacing it - so Back returns to the
/// screen the user was on. A pending tap expires after [maxPendingAge].
class NotificationNavigator {
  NotificationNavigator({
    required this._navigatorKey,
    required this._tracker,
    required this._session,
    this.onOpened,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now {
    _tracker.addListener(flush);
  }

  static const Duration maxPendingAge = Duration(minutes: 2);

  /// Screens on which the app is not yet "inside" - a held tap waits here.
  static const Set<String> _notReadyRoutes = {
    RouteNames.splash,
    RouteNames.onboarding,
    RouteNames.login,
    RouteNames.signUp,
    RouteNames.forgotPassword,
  };

  final GlobalKey<NavigatorState> _navigatorKey;
  final NotificationRouteTracker _tracker;
  final NotificationSession Function() _session;
  final DateTime Function() _clock;

  /// Called after a destination was actually opened (the lifecycle uses it to
  /// mark the matching inbox row read, best-effort).
  final void Function(NotificationPayload payload)? onOpened;

  NotificationPayload? _pending;
  DateTime? _pendingAt;

  bool get hasPending => _pending != null;

  /// Records the tap and opens it as soon as the app is ready (immediately
  /// when it already is). Idempotent for the double delivery of
  /// `getInitialMessage` + `onMessageOpenedApp`: a second tap on the same
  /// notification simply navigates again only if it arrives again.
  void open(NotificationPayload payload) {
    _pending = payload;
    _pendingAt = _clock();
    flush();
  }

  /// Consumes the held tap if (and only if) the app is ready.
  void flush() {
    final payload = _pending;
    if (payload == null) return;

    final at = _pendingAt;
    if (at != null && _clock().difference(at) > maxPendingAge) {
      _pending = null;
      _pendingAt = null;
      return;
    }

    final nav = _navigatorKey.currentState;
    final name = _tracker.currentName;
    if (nav == null || name == null || _notReadyRoutes.contains(name)) return;

    _pending = null;
    _pendingAt = null;
    final destination = NotificationRouter.resolve(payload, _session());
    if (destination == null) return;
    nav.pushNamed(destination.routeName, arguments: destination.arguments);
    onOpened?.call(payload);
  }

  /// Whether the user is ALREADY on the screen [payload] points to (the
  /// foreground banner is then pointless and is skipped).
  bool isShowing(NotificationPayload payload) {
    final destination = NotificationRouter.resolve(payload, _session());
    return destination != null &&
        _tracker.currentName == destination.routeName &&
        _tracker.currentArguments == destination.arguments;
  }

  void dispose() => _tracker.removeListener(flush);
}
