import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../app/routes/route_names.dart';
import '../services/notification_lifecycle.dart';
import '../services/notification_route_tracker.dart';

/// Starts the [NotificationLifecycle] once for the running app and shows the
/// one-time Admin notification explainer the first time the Admin dashboard
/// is on screen. Wrapped around the app by `TWinArApp` ONLY when
/// `enableNotifications` is true (production `main.dart`); widget tests that
/// pump `TWinArApp` never mount it.
class NotificationHost extends StatefulWidget {
  const NotificationHost({super.key, required this.child});

  final Widget child;

  @override
  State<NotificationHost> createState() => _NotificationHostState();
}

class _NotificationHostState extends State<NotificationHost> {
  NotificationLifecycle? _lifecycle;
  bool _adminPrompted = false;

  @override
  void initState() {
    super.initState();
    final lifecycle = context.read<NotificationLifecycle>();
    _lifecycle = lifecycle;
    NotificationRouteTracker.instance.addListener(_onRoute);
    lifecycle.start();
  }

  void _onRoute() {
    final lifecycle = _lifecycle;
    if (lifecycle == null) return;
    if (!lifecycle.session.isSuperAdmin) {
      _adminPrompted = false; // a later admin login prompts again (once)
      return;
    }
    if (NotificationRouteTracker.instance.currentName ==
            RouteNames.adminDashboard &&
        !_adminPrompted) {
      _adminPrompted = true;
      lifecycle.maybePromptAdmin();
    }
  }

  @override
  void dispose() {
    NotificationRouteTracker.instance.removeListener(_onRoute);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Zero-size widget placed on the order-result screen: once, after the first
/// frame, offers the contextual notification opt-in (plan D14, moment #1).
/// The lifecycle decides whether to actually show anything (customer, not
/// already granted, not already declined). Reads the lifecycle optionally, so
/// trees without it (tests) are unaffected.
class NotificationOptInTrigger extends StatefulWidget {
  const NotificationOptInTrigger({super.key});

  @override
  State<NotificationOptInTrigger> createState() =>
      _NotificationOptInTriggerState();
}

class _NotificationOptInTriggerState extends State<NotificationOptInTrigger> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final lifecycle = context.read<NotificationLifecycle?>();
      if (lifecycle != null && lifecycle.isStarted) {
        lifecycle.maybePromptAfterOrder();
      }
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
