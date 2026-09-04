import 'package:flutter/foundation.dart';

import '../../features/cart/models/cart_item_model.dart';
import '../models/product/product_color_option.dart';
import '../models/product/product_size.dart';

/// Cart quantity bounds (Phase 8.10 approved decision).
const int cartMinQuantity = 1;
const int cartMaxQuantity = 99;

/// Canonical `users/{uid}/cart` data contract (Phase 8.10), mirroring
/// [AddressRepository]/[FavoritesRepository]'s shape: synchronous/reactive
/// reads, `Future`-based writes, owner-scoped (uid) subscriptions in the
/// real implementation.
///
/// Every method here operates on the domain `(productId, selectedColor,
/// selectedSize)` tuple, never a raw Firestore document ID - the
/// deterministic, collision-safe key a real implementation derives from
/// that tuple (see `cart_item_key.dart`) is an internal Firestore
/// implementation detail, not part of this contract, so a caller can never
/// accidentally pass the wrong kind of string.
///
/// `priceAmountSnapshot` is accepted here (and persisted server-side, per
/// the locked schema) purely as a DISPLAY cache - see [CartRepository]'s
/// consumers. It is never read back into [CartItemModel] and must never be
/// trusted for pricing/charging (Checkout always re-resolves live product
/// prices - see `CheckoutViewModel`).
abstract class CartRepository extends ChangeNotifier {
  bool get isLoading;
  bool get hasError;

  List<CartItemModel> get items;

  int get itemCount => items.fold(0, (sum, item) => sum + item.quantity);

  /// Adds [quantity] (clamped to [cartMinQuantity]..[cartMaxQuantity]) of a
  /// product/variant to the cart. If a line for the exact same
  /// `(productId, selectedColor, selectedSize)` tuple already exists, its
  /// quantity is atomically INCREMENTED (and clamped to
  /// [cartMaxQuantity]) rather than a second line being created - this is
  /// what makes "adding the same product/variant from two devices" merge
  /// correctly instead of racing.
  Future<void> addItem({
    required String productId,
    int quantity = 1,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
    int priceAmountSnapshot = 0,
  });

  /// Sets the ABSOLUTE quantity (clamped to [cartMinQuantity]..
  /// [cartMaxQuantity]) for an existing line. Use [removeItem] to remove a
  /// line entirely - this method never removes on a low value, matching the
  /// pre-Phase-8.10 `CustomerShoppingState.updateQuantity` convention.
  Future<void> setQuantity({
    required String productId,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
    required int quantity,
  });

  Future<void> removeItem({
    required String productId,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
  });

  /// Removes every line for the current user - called once after a
  /// successful Checkout submit.
  Future<void> clear();
}
