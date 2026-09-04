import 'package:flutter/foundation.dart';
import '../../core/models/order/order_model.dart';
import '../../core/data/commerce_database.dart';

class CustomerOrderState extends ChangeNotifier {
  final CommerceDatabase _db;

  CustomerOrderState(this._db) {
    _db.addListener(notifyListeners);
  }

  @override
  void dispose() {
    _db.removeListener(notifyListeners);
    super.dispose();
  }

  List<OrderModel> get orders => _db.orders;

  OrderModel? getOrderById(String id) {
    try {
      return _db.orders.firstWhere((order) => order.id == id);
    } catch (e) {
      return null;
    }
  }
}
