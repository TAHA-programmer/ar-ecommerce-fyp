import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../app/routes/route_names.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/feedback/app_toast.dart';
import '../../../core/widgets/states/app_empty_state.dart';
import '../../../core/widgets/states/app_error_state.dart';
import '../../../core/widgets/states/app_loading_indicator.dart';
import '../models/app_notification.dart';
import '../repositories/notification_inbox_repository.dart';
import '../services/notification_lifecycle.dart';
import '../services/notification_permission_service.dart';
import '../services/notification_router.dart';
import '../widgets/notification_permission_banner.dart';
import '../widgets/notification_tile.dart';

/// The customer Notification Centre (`/notifications`): the server-written
/// inbox of order / refund / review-moderation events, newest first, grouped
/// by day. It is the SOURCE OF TRUTH - a push is only a convenience (delivery
/// is never guaranteed), so every event is here whether or not the user
/// allowed or even received the push.
///
/// States: loading (first snapshot only) / empty / error with retry (the
/// last-known list is kept on a transient error) / list. Works offline from
/// the Firestore cache.
class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key, this.clock});

  /// Test seam for "now" (relative times, day headers).
  final DateTime Function()? clock;

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  NotificationPermissionStatus? _permission;
  bool _bannerDismissed = false;

  /// Rows swiped away, hidden immediately (a Dismissible must leave the tree
  /// in the same frame) while the delete is in flight; restored on failure.
  final Set<String> _swiped = {};

  @override
  void initState() {
    super.initState();
    _loadPermission();
  }

  Future<void> _loadPermission() async {
    final service = context.read<NotificationPermissionService?>();
    if (service == null) return;
    final status = await service.status();
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _turnOn() async {
    final lifecycle = context.read<NotificationLifecycle?>();
    if (lifecycle == null) return;
    final status = await lifecycle.requestFromSettings(admin: false);
    if (mounted) setState(() => _permission = status);
  }

  Future<void> _open(
    NotificationInboxRepository repo,
    AppNotification n,
  ) async {
    if (n.isUnread) repo.markRead(n.id); // fire-and-forget; row updates live
    final destination = NotificationRouter.resolveInboxRow(n);
    if (destination == null) return;
    Navigator.of(
      context,
    ).pushNamed(destination.routeName, arguments: destination.arguments);
  }

  Future<void> _dismiss(
    NotificationInboxRepository repo,
    AppNotification n,
  ) async {
    setState(() => _swiped.add(n.id));
    final ok = await repo.delete(n.id);
    if (!mounted) return;
    if (!ok) {
      // Let the frame that REMOVED the dismissed row render first: restoring
      // in the same frame would keep a dismissed Dismissible in the tree (a
      // framework assertion) whenever the delete fails fast.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      setState(() => _swiped.remove(n.id));
      AppToast.error(context, "Couldn't remove that notification.");
    }
  }

  @override
  Widget build(BuildContext context) {
    final repo = context.watch<NotificationInboxRepository>();
    final now = (widget.clock ?? DateTime.now)();
    final showBanner =
        !_bannerDismissed &&
        _permission != null &&
        _permission != NotificationPermissionStatus.granted;

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            _buildTitleRow(context, repo),
            if (showBanner)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.m),
                child: NotificationPermissionBanner(
                  status: _permission!,
                  onTurnOn: _turnOn,
                  onDismiss: () => setState(() => _bannerDismissed = true),
                ),
              ),
            Expanded(child: _buildBody(context, repo, now)),
          ],
        ),
      ),
    );
  }

  Widget _buildTitleRow(
    BuildContext context,
    NotificationInboxRepository repo,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.xs,
        AppSpacing.s,
        AppSpacing.xs,
        AppSpacing.s,
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('notifications_back_button'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.arrow_back),
          ),
          const SizedBox(width: AppSpacing.xxs),
          Expanded(child: Text('Notifications', style: AppTypography.title)),
          if (repo.unreadCount > 0)
            TextButton(
              key: const Key('notifications_mark_all_read'),
              onPressed: () async {
                final ok = await repo.markAllRead();
                if (!ok && context.mounted) {
                  AppToast.error(
                    context,
                    "Couldn't update your notifications. Please try again.",
                  );
                }
              },
              child: Text(
                'Mark all read',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          IconButton(
            key: const Key('notifications_settings_button'),
            tooltip: 'Notification settings',
            onPressed: () => Navigator.of(
              context,
            ).pushNamed(RouteNames.notificationSettings),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    NotificationInboxRepository repo,
    DateTime now,
  ) {
    final items = repo.notifications
        .where((n) => !_swiped.contains(n.id))
        .toList();

    if (repo.isLoading && items.isEmpty) return const AppLoadingIndicator();

    if (repo.hasError && items.isEmpty) {
      return AppErrorState(
        message:
            "We couldn't load your notifications. Check your connection and "
            'try again.',
        onRetry: repo.retry,
      );
    }

    if (items.isEmpty) {
      return const AppEmptyState(
        title: 'No notifications yet',
        message: 'Order updates and account alerts will appear here.',
        icon: Icons.notifications_none,
      );
    }

    final children = <Widget>[];
    String? lastLabel;
    for (final n in items) {
      final label = notificationDayLabel(n.createdAt, now);
      if (label != lastLabel) {
        lastLabel = label;
        children.add(
          Padding(
            padding: const EdgeInsets.only(
              top: AppSpacing.xs,
              bottom: AppSpacing.xs,
            ),
            child: Text(
              label,
              style: AppTypography.bodyMedium.copyWith(
                fontWeight: FontWeight.w700,
                color: AppColors.primaryDark,
              ),
            ),
          ),
        );
      }
      children.add(
        Dismissible(
          key: ValueKey('notification_${n.id}'),
          direction: DismissDirection.endToStart,
          background: Container(
            alignment: Alignment.centerRight,
            padding: const EdgeInsets.only(right: AppSpacing.m),
            margin: const EdgeInsets.only(bottom: AppSpacing.s),
            decoration: BoxDecoration(
              color: AppColors.error.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Icon(Icons.delete_outline, color: AppColors.error),
          ),
          onDismissed: (_) => _dismiss(repo, n),
          child: NotificationTile(
            notification: n,
            now: now,
            onTap: () => _open(repo, n),
          ),
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        0,
        AppSpacing.m,
        AppSpacing.m,
      ),
      children: children,
    );
  }
}
