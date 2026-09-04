import 'package:flutter/foundation.dart';
import '../models/order/order_model.dart';
import '../models/order/payment_record.dart';
import '../models/product/product_model.dart';

/// Canonical commerce-data contract shared by Customer and Admin.
///
/// Reads stay synchronous and reactive: implementations maintain a local
/// list and call [notifyListeners] on change, so every existing
/// [addListener]/[ChangeNotifier] consumption pattern keeps working
/// unchanged regardless of what backs the data (in-memory today, Firestore
/// later).
///
/// Writes are [Future]-based from this contract's inception so a later
/// Firestore-backed implementation is a drop-in with no second contract
/// change. [MockCommerceDatabase] resolves every write synchronously under
/// the hood; callers should still `await` for forward compatibility.
abstract class CommerceDatabase extends ChangeNotifier {
  static const int lowStockThreshold = 5;

  List<ProductModel> get products;
  List<OrderModel> get orders;
  List<PaymentRecord> get payments;

  ProductModel getProductById(String id);

  /// Admin's own product-catalog edit of stock (Admin Inventory). A
  /// genuine product-catalog write, exactly like [addProduct]/
  /// [updateProduct]/[setProductActive]/[deleteProduct].
  ///
  /// Phase 8.11: this stamps a server-resolved `lastStockUpdatedAt`
  /// alongside the new quantity in a plain (non-transactional)
  /// single-document update. Phase 8.13.6: this is now the ONLY client
  /// stock-write path - checkout's sale-driven stock movement (reserve /
  /// restore) is entirely server-side in the Cloud Functions.
  Future<void> addProduct(ProductModel product);
  Future<void> updateProduct(ProductModel product);
  Future<void> setProductActive(String productId, bool isActive);
  Future<void> updateStock(String productId, int newStockQuantity);
  Future<void> deleteProduct(String productId);

  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus);

  // Phase 8.13.6 - Final Security Cutover: `submitOrderWithPayment` and
  // `recordOrderStockDecrement` were removed from this contract. Orders,
  // payments and checkout stock reservations are now created EXCLUSIVELY by
  // the Cloud Functions (`createPaymentIntent` reserves stock + writes the
  // `checkoutSessions` doc; `stripeWebhook` / `releaseExpiredReservations`
  // create the `orders`/`payments` documents), all via the Admin SDK. The
  // Flutter client only ever READS `orders`/`payments` (through the
  // subscriptions this class owns) and drives Stripe through
  // `CheckoutPaymentService`. `firestore.rules` enforces this: `orders`/
  // `payments` `create` is `if false` for every client.
  //
  // [MockCommerceDatabase] keeps standalone `addOrder`/`addPayment` fixture
  // helpers for test seeding - they are NOT on this abstract type and are
  // only reachable when a test holds a concrete `MockCommerceDatabase`.
}
