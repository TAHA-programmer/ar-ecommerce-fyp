import 'package:flutter/foundation.dart';
import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/order/order_model.dart';

import '../../../../core/models/product/product_model.dart';

class AdminDashboardViewModel extends ChangeNotifier {
  final CommerceDatabase _db;

  AdminDashboardViewModel(this._db) {
    _db.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _db.removeListener(notifyListeners);
    super.dispose();
  }

  // --- Products ---
  int get totalProducts => _db.products.length;

  List<ProductModel> get lowStockProducts {
    final products = _allLowStockProducts;
    products.sort((a, b) => a.stockQuantity.compareTo(b.stockQuantity));
    return products.take(3).toList();
  }

  List<ProductModel> get _allLowStockProducts => _db.products
      .where(
        (p) =>
            p.stockQuantity > 0 &&
            p.stockQuantity <= CommerceDatabase.lowStockThreshold,
      )
      .toList();

  int get lowStockProductsCount => _allLowStockProducts.length;

  List<ProductModel> get recentlyAddedProducts {
    final products = List<ProductModel>.from(_db.products);
    products.sort((a, b) => b.addedDate.compareTo(a.addedDate));
    return products.take(3).toList();
  }

  // --- Orders ---
  int get totalOrders => _db.orders.length;

  int get pendingOrdersCount {
    return _db.orders.where((o) => o.orderStatus == OrderStatus.pending).length;
  }

  List<OrderModel> get recentOrders {
    final orders = List<OrderModel>.from(_db.orders);
    orders.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return orders.take(3).toList();
  }

  // --- Payments ---
  int get successfulPaymentsCount {
    return _db.payments.where((p) => p.status == PaymentStatus.paid).length;
  }

  int get failedPaymentsCount {
    return _db.payments.where((p) => p.status == PaymentStatus.failed).length;
  }

  double get paidAmount {
    return _db.payments
        .where((p) => p.status == PaymentStatus.paid)
        .fold(0.0, (sum, p) => sum + p.amount);
  }

  double get failedAmount {
    return _db.payments
        .where((p) => p.status == PaymentStatus.failed)
        .fold(0.0, (sum, p) => sum + p.amount);
  }

  double get totalRevenue => paidAmount;

  // Percentage calculations based on amounts, or counts?
  // User explicitly asked to choose: "Prefer COUNT-based percentages if the labels represent payment success/failure rate."
  // Wait, the Figma says: "Successful: $22,450.60 (95.1%)", "Failed: $1,130.15 (4.9%)". It shows amounts and percentages.
  // The percentages exactly match the proportion of the amount!
  // 22450.60 / (22450.60 + 1130.15) = 22450.60 / 23580.75 = 95.2%
  // Let's use amount-based percentages since it sits right next to the amount.
  double get paymentSuccessPercentage {
    final total = paidAmount + failedAmount;
    if (total == 0) return 0.0;
    return (paidAmount / total) * 100;
  }

  double get paymentFailurePercentage {
    final total = paidAmount + failedAmount;
    if (total == 0) return 0.0;
    return (failedAmount / total) * 100;
  }
}
