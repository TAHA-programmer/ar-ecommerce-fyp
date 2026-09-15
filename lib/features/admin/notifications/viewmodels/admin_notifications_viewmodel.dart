import 'package:flutter/foundation.dart';

import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/order/order_model.dart';
import '../../../../core/models/product/product_model.dart';

/// Backs the Admin Notifications screen (reached from the header's
/// notification bell). Every item is derived directly from the shared
/// [CommerceDatabase] - the same source Dashboard/Inventory/Orders already
/// read - so there is nothing here that could be a fake/synthetic alert.
///
/// [CommerceDatabase] exposes no separate loading/error state on its
/// abstract contract (see its doc comment), and none of the other Admin
/// screens built on it (Dashboard, Products, Inventory, Orders) surface one
/// either - this follows that same established precedent rather than
/// inventing a loading state the rest of the app doesn't have.
class AdminNotificationsViewModel extends ChangeNotifier {
  final CommerceDatabase _db;

  AdminNotificationsViewModel(this._db) {
    _db.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _db.removeListener(notifyListeners);
    super.dispose();
  }

  /// Low-stock, still-in-stock products, nearest to zero first - mirrors
  /// `AdminDashboardViewModel.lowStockProducts`' ordering but with no cap,
  /// since this screen's whole purpose is to show every one of them.
  List<ProductModel> get lowStockProducts {
    final products = _db.products
        .where(
          (p) =>
              p.stockQuantity > 0 &&
              p.stockQuantity <= CommerceDatabase.lowStockThreshold,
        )
        .toList();
    products.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
    return products;
  }

  /// Orders still awaiting confirmation, most recent first.
  List<OrderModel> get pendingOrders {
    final orders = _db.orders
        .where((o) => o.orderStatus == OrderStatus.pending)
        .toList();
    orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return orders;
  }

  bool get hasNotifications =>
      lowStockProducts.isNotEmpty || pendingOrders.isNotEmpty;
}
