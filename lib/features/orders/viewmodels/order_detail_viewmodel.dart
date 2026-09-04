// ignore_for_file: prefer_initializing_formals

import 'package:flutter/foundation.dart';
import '../../../../app/viewmodels/customer_order_state.dart';
import '../../../../core/models/order/order_model.dart';

class OrderDetailViewModel extends ChangeNotifier {
  final CustomerOrderState _orderState;
  final String orderId;

  OrderModel? _order;
  bool _isNotFound = false;

  OrderDetailViewModel({
    required CustomerOrderState orderState,
    required this.orderId,
  }) : _orderState = orderState {
    _orderState.addListener(_loadOrder);
    _loadOrder();
  }

  OrderModel? get order => _order;
  bool get isNotFound => _isNotFound;

  @override
  void dispose() {
    _orderState.removeListener(_loadOrder);
    super.dispose();
  }

  void _loadOrder() {
    _order = _orderState.getOrderById(orderId);
    _isNotFound = _order == null;
    notifyListeners();
  }
}
