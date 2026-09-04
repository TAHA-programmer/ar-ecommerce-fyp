import 'package:flutter/foundation.dart';

import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/order/order_model.dart';
import '../../../../core/models/order/payment_record.dart';

/// Owns Admin Payments-tab search/filter state on top of the shared
/// [CommerceDatabase]. Kept separate from [AdminOrdersViewModel] so the
/// already-approved, physically-tested Orders tab is never touched by
/// Payments work. Read-only - it never mutates a [PaymentRecord], it only
/// searches, filters, sorts, and safely resolves the linked order for the
/// canonical list that Customer checkout writes to.
class AdminPaymentsViewModel extends ChangeNotifier {
  final CommerceDatabase _db;

  AdminPaymentsViewModel(this._db) {
    _db.addListener(_onDatabaseChanged);
  }

  String _searchQuery = '';
  String get searchQuery => _searchQuery;

  PaymentStatus? _statusFilter; // null means 'All'
  PaymentStatus? get statusFilter => _statusFilter;

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

  void setStatusFilter(PaymentStatus? status) {
    _statusFilter = status;
    notifyListeners();
  }

  /// Safely resolves the order a payment is linked to. Returns null when
  /// [PaymentRecord.orderId] does not match any order currently in the
  /// shared database - the UI must render a graceful fallback, never crash.
  /// (As of Phase 8.9 every payment is created atomically with its order,
  /// so this should always resolve for real data - the try/catch stays as
  /// defensive belt-and-suspenders, not because null/missing is expected.)
  OrderModel? linkedOrderFor(PaymentRecord payment) {
    try {
      return _db.orders.firstWhere((order) => order.id == payment.orderId);
    } catch (_) {
      return null;
    }
  }

  List<PaymentRecord> get filteredPayments {
    var result = _db.payments.toList();

    final query = _searchQuery.trim().toLowerCase();
    if (query.isNotEmpty) {
      result = result.where((payment) {
        final paymentIdMatches = payment.paymentId.toLowerCase().contains(
          query,
        );
        final orderIdMatches = payment.orderId.toLowerCase().contains(query);
        final customerMatches =
            linkedOrderFor(
              payment,
            )?.deliveryAddress.fullName.toLowerCase().contains(query) ??
            false;
        return paymentIdMatches || orderIdMatches || customerMatches;
      }).toList();
    }

    if (_statusFilter != null) {
      result = result
          .where((payment) => payment.status == _statusFilter)
          .toList();
    }

    result.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return result;
  }

  int get totalPaymentsCount => _db.payments.length;

  int get paidCount =>
      _db.payments.where((p) => p.status == PaymentStatus.paid).length;

  int get pendingCount =>
      _db.payments.where((p) => p.status == PaymentStatus.pending).length;

  int get failedCount =>
      _db.payments.where((p) => p.status == PaymentStatus.failed).length;
}
