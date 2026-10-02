import 'package:flutter/widgets.dart';

/// Tracks the name/arguments of the page currently on top of the app
/// Navigator, so (a) a notification tap that arrives during Splash/Login is
/// held until the app is on a real screen, and (b) a foreground banner is
/// skipped when the user is already looking at what it points to.
///
/// A single static [instance] is registered in `MaterialApp.navigatorObservers`
/// (the MaterialApp is built before the provider tree's services exist).
/// Unnamed routes (dialogs, bottom sheets) are ignored so the tracked page
/// stays the underlying screen.
class NotificationRouteTracker extends NavigatorObserver {
  NotificationRouteTracker();

  static final NotificationRouteTracker instance = NotificationRouteTracker();

  String? _name;
  Object? _arguments;
  final List<VoidCallback> _listeners = [];

  String? get currentName => _name;
  Object? get currentArguments => _arguments;

  void addListener(VoidCallback listener) => _listeners.add(listener);
  void removeListener(VoidCallback listener) => _listeners.remove(listener);

  /// Test hook.
  void debugReset() {
    _name = null;
    _arguments = null;
    _listeners.clear();
  }

  void _set(Route<dynamic>? route) {
    final name = route?.settings.name;
    if (name == null) return;
    _name = name;
    _arguments = route!.settings.arguments;
    // Notify AFTER the frame so listeners (which may navigate) never run
    // inside the Navigator's own transition bookkeeping.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final l in List.of(_listeners)) {
        l();
      }
    });
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(route);

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) =>
      _set(newRoute);

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) =>
      _set(previousRoute);
}
