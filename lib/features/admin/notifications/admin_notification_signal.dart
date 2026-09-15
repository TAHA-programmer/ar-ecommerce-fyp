import '../../../core/data/commerce_database.dart';
import '../../../core/models/order/order_model.dart';

/// How many genuinely notification-worthy items Admin currently has -
/// exactly `pendingOrders.length + lowStockProducts.length`, the same two
/// counts the Admin Notifications screen itself lists
/// ([AdminNotificationsViewModel.pendingOrders]/`.lowStockProducts`) -
/// derived from the same live [CommerceDatabase] the Dashboard/Inventory/
/// Orders screens already read. There is no separate "notifications"
/// backend, so this is never a synthetic/fake/hardcoded number.
///
/// Used by `AdminHeader` for the bell's numeric badge, and mirrored by
/// [AdminNotificationsViewModel] for the actual list content, so the badge
/// count and the screen it opens can never disagree.
int adminNotificationCount(CommerceDatabase db) {
  final lowStockCount = db.products
      .where(
        (p) =>
            p.stockQuantity > 0 &&
            p.stockQuantity <= CommerceDatabase.lowStockThreshold,
      )
      .length;
  final pendingOrdersCount = db.orders
      .where((o) => o.orderStatus == OrderStatus.pending)
      .length;
  return lowStockCount + pendingOrdersCount;
}
