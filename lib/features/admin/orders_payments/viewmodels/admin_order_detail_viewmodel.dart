import 'package:flutter/foundation.dart';

import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/order/order_model.dart';
import '../../../../core/models/order/payment_record.dart';

/// Locked lifecycle graph for this mock/frontend phase:
/// pending -> confirmed | cancelled
/// confirmed -> shipped | cancelled
/// shipped -> delivered | cancelled
/// delivered -> terminal
/// cancelled -> terminal
/// No backward moves, no skipping stages.
const Map<OrderStatus, List<OrderStatus>> _allowedOrderStatusTransitions = {
  OrderStatus.pending: [OrderStatus.confirmed, OrderStatus.cancelled],
  OrderStatus.confirmed: [OrderStatus.shipped, OrderStatus.cancelled],
  OrderStatus.shipped: [OrderStatus.delivered, OrderStatus.cancelled],
  OrderStatus.delivered: [],
  OrderStatus.cancelled: [],
};

/// Owns a single order's detail state on top of the shared
/// [CommerceDatabase]. Resolves the order and its linked payment fresh
/// from the canonical lists (never a passed-in copy), stages a candidate
/// status locally, validates transitions against the locked lifecycle graph,
/// and commits only through [CommerceDatabase.updateOrderStatus].
class AdminOrderDetailViewModel extends ChangeNotifier {
  final CommerceDatabase _db;
  final String orderId;

  OrderModel? _order;
  bool _isNotFound = false;
  OrderStatus? _stagedStatus;

  AdminOrderDetailViewModel(this._db, {required this.orderId}) {
    _db.addListener(_onDatabaseChanged);
    _loadOrder();
  }

  OrderModel? get order => _order;
  bool get isNotFound => _isNotFound;
  OrderStatus? get stagedStatus => _stagedStatus;

  @override
  void dispose() {
    _db.removeListener(_onDatabaseChanged);
    super.dispose();
  }

  void _onDatabaseChanged() => _loadOrder();

  void _loadOrder() {
    try {
      _order = _db.orders.firstWhere((o) => o.id == orderId);
      _isNotFound = false;
      // Only seed the staged value on first load (or after a not-found ->
      // found transition); an in-progress staged selection made by the
      // admin is never clobbered by an unrelated database change.
      _stagedStatus ??= _order!.orderStatus;
    } catch (_) {
      _order = null;
      _isNotFound = true;
    }
    notifyListeners();
  }

  /// Safely resolves the [PaymentRecord] linked to this order, mirroring
  /// AdminPaymentsViewModel.linkedOrderFor's reverse lookup. Null when no
  /// matching payment exists.
  PaymentRecord? get linkedPayment {
    final currentOrder = _order;
    if (currentOrder == null) return null;
    try {
      return _db.payments.firstWhere((p) => p.orderId == currentOrder.id);
    } catch (_) {
      return null;
    }
  }

  bool canTransitionTo(OrderStatus target) {
    final currentOrder = _order;
    if (currentOrder == null) return false;
    if (target == currentOrder.orderStatus) return true;
    return _allowedOrderStatusTransitions[currentOrder.orderStatus]?.contains(
          target,
        ) ??
        false;
  }

  /// Whether committing [stagedStatus] requires a confirmation dialog before
  /// applying, per the Figma note: Delivered and Cancelled only.
  bool get requiresConfirmation =>
      _stagedStatus == OrderStatus.delivered ||
      _stagedStatus == OrderStatus.cancelled;

  bool get hasPendingChange =>
      _order != null &&
      _stagedStatus != null &&
      _stagedStatus != _order!.orderStatus;

  void stageStatus(OrderStatus status) {
    if (!canTransitionTo(status)) return;
    _stagedStatus = status;
    notifyListeners();
  }

  /// Validates and commits the staged status through the shared database.
  /// Returns true on success. Never called by the UI unless a required
  /// confirmation has already been obtained.
  Future<bool> commitStatus() async {
    final currentOrder = _order;
    final target = _stagedStatus;
    if (currentOrder == null || target == null) return false;
    if (target == currentOrder.orderStatus) return false;
    if (!canTransitionTo(target)) return false;
    try {
      await _db.updateOrderStatus(currentOrder.id, target);
      return true;
    } catch (_) {
      return false;
    }
  }
}
