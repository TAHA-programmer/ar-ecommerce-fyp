import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/theme/app_radii.dart';
import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_typography.dart';
import '../../../core/widgets/states/app_error_state.dart';
import '../../../core/widgets/states/app_loading_indicator.dart';
import '../services/notification_permission_service.dart';
import '../viewmodels/notification_settings_viewmodel.dart';

/// Push-notification preferences (`/notification-settings`), shared by the
/// customer (reached from the Notification Centre and Profile) and the Admin
/// (reached from the account sheet). The signed-in role decides which
/// categories appear. Preferences gate the PUSH only; the customer's
/// Notification Centre always keeps every event.
class NotificationSettingsView extends StatefulWidget {
  const NotificationSettingsView({super.key});

  @override
  State<NotificationSettingsView> createState() =>
      _NotificationSettingsViewState();
}

class _NotificationSettingsViewState extends State<NotificationSettingsView>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Coming back from system settings: re-read the OS permission.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<NotificationSettingsViewModel>().refreshPermission();
    }
  }

  @override
  Widget build(BuildContext context) {
    final vm = context.watch<NotificationSettingsViewModel>();
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.xs,
                AppSpacing.s,
                AppSpacing.m,
                AppSpacing.s,
              ),
              child: Row(
                children: [
                  IconButton(
                    key: const Key('notification_settings_back_button'),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Text('Notification settings', style: AppTypography.title),
                ],
              ),
            ),
            Expanded(child: _buildBody(context, vm)),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context, NotificationSettingsViewModel vm) {
    if (vm.isLoading) return const AppLoadingIndicator();
    if (vm.loadFailed) {
      return AppErrorState(
        message:
            "We couldn't load your notification settings. Check your "
            'connection and try again.',
        onRetry: vm.load,
      );
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.m,
        0,
        AppSpacing.m,
        AppSpacing.l,
      ),
      children: [
        _PermissionCard(vm: vm),
        const SizedBox(height: AppSpacing.m),
        if (vm.saveError != null)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.s),
            child: Text(
              vm.saveError!,
              key: const Key('notification_settings_save_error'),
              style: AppTypography.bodySmall.copyWith(color: AppColors.error),
            ),
          ),
        Text(
          'Send me push notifications for',
          style: AppTypography.bodyMedium.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: AppSpacing.xs),
        if (vm.isAdmin) ...[
          _SwitchRow(
            switchKey: const Key('switch_admin_orders'),
            title: 'New orders',
            subtitle: 'When a customer places a paid order.',
            value: vm.prefs.pushAdminOrders,
            onChanged: vm.setPushAdminOrders,
          ),
          _SwitchRow(
            switchKey: const Key('switch_admin_stock'),
            title: 'Stock alerts',
            subtitle: 'When a product runs low or sells out.',
            value: vm.prefs.pushAdminStock,
            onChanged: vm.setPushAdminStock,
          ),
          _SwitchRow(
            switchKey: const Key('switch_admin_moderation'),
            title: 'Moderation alerts',
            subtitle: 'When a review is reported several times.',
            value: vm.prefs.pushAdminModeration,
            onChanged: vm.setPushAdminModeration,
          ),
          _SwitchRow(
            switchKey: const Key('switch_admin_payments'),
            title: 'Payment issues',
            subtitle: 'When a payment needs your attention.',
            value: vm.prefs.pushAdminPayments,
            onChanged: vm.setPushAdminPayments,
          ),
        ] else ...[
          _SwitchRow(
            switchKey: const Key('switch_orders'),
            title: 'Order updates',
            subtitle: 'Confirmed, shipped, delivered, cancelled and refunds.',
            value: vm.prefs.pushOrders,
            onChanged: vm.setPushOrders,
          ),
          _SwitchRow(
            switchKey: const Key('switch_reviews'),
            title: 'Reviews & moderation',
            subtitle: 'When a review of yours is hidden or not published.',
            value: vm.prefs.pushReviews,
            onChanged: vm.setPushReviews,
          ),
          const SizedBox(height: AppSpacing.s),
          Text(
            'Turning a category off only stops the push notification. Your '
            'Notification Centre still keeps a record of every update.',
            key: const Key('notification_settings_inbox_note'),
            style: AppTypography.bodySmall.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ],
        const SizedBox(height: AppSpacing.m),
        Text(
          'Push delivery is not guaranteed - your phone may delay or skip '
          'notifications in battery-saver mode.',
          style: AppTypography.bodySmall.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
      ],
    );
  }
}

class _PermissionCard extends StatelessWidget {
  const _PermissionCard({required this.vm});

  final NotificationSettingsViewModel vm;

  @override
  Widget build(BuildContext context) {
    final on = vm.permissionGranted;
    final blocked = vm.permissionStatus == NotificationPermissionStatus.blocked;
    return Container(
      key: const Key('notification_settings_permission_card'),
      padding: const EdgeInsets.all(AppSpacing.s),
      decoration: BoxDecoration(
        color: on
            ? AppColors.primary.withValues(alpha: 0.08)
            : AppColors.warning.withValues(alpha: 0.10),
        borderRadius: AppRadii.largeBorder,
        border: Border.all(
          color: on
              ? AppColors.primary.withValues(alpha: 0.5)
              : AppColors.warning.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          Icon(
            on
                ? Icons.notifications_active_outlined
                : Icons.notifications_off_outlined,
            color: on ? AppColors.primaryDark : AppColors.warning,
          ),
          const SizedBox(width: AppSpacing.s),
          Expanded(
            child: Text(
              on
                  ? 'Notifications are allowed on this phone.'
                  : blocked
                  ? 'Notifications are blocked for TWin AR in system settings.'
                  : 'Notifications are off on this phone.',
              style: AppTypography.bodyMedium,
            ),
          ),
          if (!on)
            TextButton(
              key: const Key('notification_settings_turn_on'),
              onPressed: vm.turnOnNotifications,
              child: Text(
                blocked ? 'Open settings' : 'Turn on',
                style: AppTypography.bodySmall.copyWith(
                  color: AppColors.primaryDark,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.switchKey,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final Key switchKey;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      key: switchKey,
      contentPadding: EdgeInsets.zero,
      activeThumbColor: AppColors.primary,
      title: Text(title, style: AppTypography.bodyMedium),
      subtitle: Text(
        subtitle,
        style: AppTypography.bodySmall.copyWith(color: AppColors.textSecondary),
      ),
      value: value,
      onChanged: onChanged,
    );
  }
}
