import 'package:flutter/foundation.dart';

import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/order/order_model.dart';

/// Owns Admin Orders-tab search/filter state on top of the shared
/// [CommerceDatabase]. Read-only with respect to order status - it never
/// mutates an order, it only searches, filters, and sorts the canonical
/// list that Customer checkout writes to.
class AdminOrdersViewModel extends ChangeNotifier {
  final CommerceDatabase _db;

  AdminOrdersViewModel(this._db) {
    _db.addListener(_onDatabaseChanged);
  }

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  OrderStatus? _statusFilter; // null means 'All'
  OrderStatus? get statusFilter => _statusFilter;

  PaymentStatus? _paymentStatusFilter; // null means 'All'
  PaymentStatus? get paymentStatusFilter => _paymentStatusFilter;

  void _onDatabaseChanged() => notifyListeners();

  @override
  void dispose() {
    _db.removeListener(_onDatabaseChanged);
    super.dispose();
  }

  void setSearchQuery(String query) {
    _searchQuery = query;
    notifyListeners();
  }

  void setStatusFilter(OrderStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  void setPaymentStatusFilter(PaymentStatus? status) {
    _paymentStatusFilter = status;
    notifyListeners();
  }

  bool get hasActiveFilters =>
      _statusFilter != null || _paymentStatusFilter != null;

  List<OrderModel> get filteredOrders {
    var result = _db.orders.toList();

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((order) {
        final idMatches = order.id.toLowerCase().contains(query);
        final nameMatches = order.deliveryAddress.fullName
            .toLowerCase()
            .contains(query);
        return idMatches || nameMatches;
      }).toList();
    }

    if (_statusFilter != null) {
      result = result
          .where((order) => order.orderStatus == _statusFilter)
          .toList();
    }

    if (_paymentStatusFilter != null) {
      result = result
          .where((order) => order.paymentStatus == _paymentStatusFilter)
          .toList();
    }

    result.sort((a, b) => b.orderDate.compareTo(a.orderDate));
    return result;
  }

  int get totalOrdersCount => _db.orders.length;
}
