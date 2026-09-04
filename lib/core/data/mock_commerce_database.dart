import 'package:flutter/foundation.dart' show visibleForTesting;

import 'commerce_database.dart';
import 'mock_product_seed_data.dart';
import '../models/order/order_model.dart';
import '../models/order/payment_record.dart';
import '../models/product/product_model.dart';

class MockCommerceDatabase extends CommerceDatabase {
  final List<ProductModel> _products = [];
  final List<OrderModel> _orders = [];
  final List<PaymentRecord> _payments = [];

  MockCommerceDatabase() {
    // Seed data lives in mock_product_seed_data.dart (extracted Phase 8.5)
    // so tool/export_product_seed.dart can reuse the exact same data under
    // a plain `dart run`, which can't compile anything importing
    // package:flutter/... (needs dart:ui). Pure relocation - identical
    // products, same order, same fields.
    _products.addAll(buildMockProductSeedData());
  }

  @override
  List<ProductModel> get products => List.unmodifiable(_products);
  @override
  List<OrderModel> get orders => List.unmodifiable(_orders);
  @override
  List<PaymentRecord> get payments => List.unmodifiable(_payments);

  // Product Operations
  @override
  ProductModel getProductById(String id) {
    return _products.firstWhere(
      (p) => p.id == id,
      orElse: () => throw StateError('Product not found: $id'),
    );
  }

  @override
  Future<void> addProduct(ProductModel product) async {
    _products.add(product);
    notifyListeners();
  }

  @override
  Future<void> updateProduct(ProductModel product) async {
    final index = _products.indexWhere((p) => p.id == product.id);
    if (index != -1) {
      _products[index] = product;
      notifyListeners();
    }
  }

  @override
  Future<void> setProductActive(String productId, bool isActive) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _products[index] = _products[index].copyWith(isActive: isActive);
      notifyListeners();
    }
  }

  /// Strictly-increasing stand-in for `FieldValue.serverTimestamp()` so the
  /// Mock's `lastStockUpdatedAt` behaves like the real backend's: every
  /// stock update produces a distinct, later value, even for two updates in
  /// the same microsecond (which `DateTime.now()` alone cannot guarantee).
  DateTime? _lastStockStamp;
  DateTime _nextStockStamp() {
    final now = DateTime.now();
    final next = (_lastStockStamp == null || now.isAfter(_lastStockStamp!))
        ? now
        : _lastStockStamp!.add(const Duration(microseconds: 1));
    _lastStockStamp = next;
    return next;
  }

  /// Phase 8.11: Admin Inventory's manual stock edit - stamps
  /// `lastStockUpdatedAt` (mirrors `FirestoreCommerceDatabase.updateStock`).
  /// Phase 8.13.6: this is the ONLY stock-write path on this mock now -
  /// checkout's sale-driven stock movement is entirely server-side.
  @override
  Future<void> updateStock(String productId, int newStockQuantity) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    _products[index] = _products[index].copyWith(
      stockQuantity: newStockQuantity,
      lastStockUpdatedAt: _nextStockStamp(),
    );
    notifyListeners();
  }

  /// Test-only seam: mirror the brief window on the real Firestore path where
  /// `updateStock` has committed the new `stockQuantity` but its
  /// `FieldValue.serverTimestamp()` has not resolved yet, so
  /// `lastStockUpdatedAt` still reads as its prior value. The Phase 8.11
  /// [AdminInventoryViewModel] optimistic-then-converge timestamp behaviour
  /// depends on distinguishing that window from a fully-resolved write.
  @visibleForTesting
  Future<void> debugUpdateStockQuantityOnly(
    String productId,
    int newStockQuantity,
  ) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index == -1) return;
    _products[index] = _products[index].copyWith(
      stockQuantity: newStockQuantity,
    );
    notifyListeners();
  }

  @override
  Future<void> deleteProduct(String productId) async {
    final index = _products.indexWhere((p) => p.id == productId);
    if (index != -1) {
      _products.removeAt(index);
      notifyListeners();
    }
  }

  // Order Operations
  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {
    final index = _orders.indexWhere((o) => o.id == orderId);
    if (index != -1) {
      _orders[index] = _orders[index].copyWith(orderStatus: newStatus);
      notifyListeners();
    }
  }

  /// Mock-only fixture helper for tests that need to seed a pre-existing
  /// order without going through checkout. Deliberately NOT part of the
  /// abstract [CommerceDatabase] contract - only reachable when a test holds
  /// a concrete [MockCommerceDatabase] reference, never through the shared
  /// interface type production code depends on. (Phase 8.13.6 removed
  /// `submitOrderWithPayment`: real orders/payments are Cloud-Function-only.)
  void addOrder(OrderModel order) {
    _orders.insert(0, order);
    notifyListeners();
  }

  /// Mock-only fixture helper - see [addOrder]'s doc comment.
  void addPayment(PaymentRecord payment) {
    _payments.insert(0, payment);
    notifyListeners();
  }
}
