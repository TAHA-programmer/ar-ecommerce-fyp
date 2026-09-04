import 'package:flutter/foundation.dart';
import '../../../app/viewmodels/customer_order_state.dart';
import '../../../core/models/order/order_model.dart';

class MyOrdersViewModel extends ChangeNotifier {
  final CustomerOrderState orderState;

  OrderStatus? _selectedFilter; // null means 'All'

  MyOrdersViewModel({required this.orderState}) {
    // Listen to changes in the global order state
    orderState.addListener(_onOrderStateChanged);
  }

  @override
  void dispose() {
    orderState.removeListener(_onOrderStateChanged);
    super.dispose();
  }

  void _onOrderStateChanged() {
    notifyListeners();
  }

  OrderStatus? get selectedFilter => _selectedFilter;

  void setFilter(OrderStatus? filter) {
    if (_selectedFilter != filter) {
      _selectedFilter = filter;
      notifyListeners();
    }
  }

  List<OrderModel> get filteredOrders {
    final List<OrderModel> allOrders = orderState.orders;

    List<OrderModel> result = allOrders;

    // Apply filtering
    if (_selectedFilter != null) {
      result = result
          .where((order) => order.orderStatus == _selectedFilter)
          .toList();
    } else {
      // Just copy the list if no filter so we don't sort the immutable list directly
      result = result.toList();
    }

    // Apply sorting (newest first)
    result.sort((a, b) => b.orderDate.compareTo(a.orderDate));

    return result;
  }
}
