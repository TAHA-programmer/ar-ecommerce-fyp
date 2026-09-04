import 'package:cloud_firestore/cloud_firestore.dart';

import '../../features/cart/models/cart_item_model.dart';
import '../models/product/product_color_option.dart';
import '../models/product/product_size.dart';

// Firestore <-> CartItemModel mapping for `users/{uid}/cart/{cartItemKey}`
// (Phase 8.10, see `cart_item_key.dart` for how `cartItemKey` itself is
// derived). Explicit `is T` type checks throughout - never an unsafe cast -
// matching every other mapper in this codebase; an unrecognized
// selectedColor/selectedSize name degrades to `null` (not a crash, not a
// guess) since both are genuinely optional fields.

String _str(dynamic v, [String fallback = '']) => v is String ? v : fallback;
int _intOr(dynamic v, [int fallback = 0]) => v is num ? v.toInt() : fallback;

DateTime _dateFromTimestamp(dynamic value) {
  if (value is Timestamp) return value.toDate();
  return DateTime.now();
}

ProductColorOption? _colorFromName(dynamic v) {
  if (v is! String) return null;
  for (final c in ProductColorOption.values) {
    if (c.name == v) return c;
  }
  return null;
}

ProductSize? _sizeFromName(dynamic v) {
  if (v is! String) return null;
  for (final s in ProductSize.values) {
    if (s.name == v) return s;
  }
  return null;
}

/// Read direction: a Firestore `cart/{cartItemKey}` document ->
/// [CartItemModel]. `priceAmountSnapshot`/`addedAt`/`updatedAt` are stored
/// server-side (display-only cache / ordering metadata) but are NOT part of
/// [CartItemModel] itself - the UI always re-resolves live product data via
/// `ProductDetailsRepository`, per Correction 3
/// (`09_BACKEND_INTEGRATION_PLAN.md`), so there is nothing for the read
/// direction to hand back here beyond the four fields the app actually
/// consumes.
CartItemModel cartItemModelFromFirestore(Map<String, dynamic> data) {
  return CartItemModel(
    productId: _str(data['productId']),
    quantity: _intOr(data['quantity'], 1).clamp(1, 99),
    selectedColor: _colorFromName(data['selectedColor']),
    selectedSize: _sizeFromName(data['selectedSize']),
  );
}

/// Write direction for a brand-new cart line (first add for this
/// product+variant tuple on this device/session). `addedAt` is set once and
/// never overwritten by a later merge - see
/// `FirestoreCartRepository.addItem`'s doc comment.
Map<String, dynamic> cartItemToFirestoreCreateMap({
  required String productId,
  required int quantity,
  ProductColorOption? selectedColor,
  ProductSize? selectedSize,
  required int priceAmountSnapshot,
}) {
  return {
    'productId': productId,
    'quantity': quantity,
    'selectedColor': selectedColor?.name,
    'selectedSize': selectedSize?.name,
    'priceAmountSnapshot': priceAmountSnapshot,
    'addedAt': FieldValue.serverTimestamp(),
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Update map for merging into an existing line (quantity change from a
/// repeat add, or an absolute quantity set) - `addedAt` is deliberately
/// absent so it is never touched after creation.
Map<String, dynamic> cartItemToFirestoreUpdateMap({
  required int quantity,
  int? priceAmountSnapshot,
}) {
  return {
    'quantity': quantity,
    'priceAmountSnapshot': ?priceAmountSnapshot,
    'updatedAt': FieldValue.serverTimestamp(),
  };
}

/// Test-only convenience mirroring `_dateFromTimestamp` for repository code
/// that needs the raw `addedAt`/`updatedAt` (the repository's own ordering,
/// not the UI-facing [CartItemModel]).
DateTime cartTimestampFromData(Map<String, dynamic> data, String key) =>
    _dateFromTimestamp(data[key]);
