import 'package:flutter/foundation.dart';

import '../../features/cart/models/cart_item_model.dart';
import '../models/product/product_color_option.dart';
import '../models/product/product_size.dart';
import 'cart_repository.dart';

/// In-memory test double for [CartRepository] - not used in production.
/// Mirrors `MockCategoryRepository`/`MockAddressRepository`'s role. Keyed
/// internally by [CartItemModel.id] (the local composite key) purely as a
/// convenient Map key for this in-memory double - it never touches
/// Firestore, so the doc-ID-safety concern `cart_item_key.dart` exists for
/// simply doesn't apply here.
class MockCartRepository extends CartRepository {
  final Map<String, CartItemModel> _items;
  bool _isLoading;
  bool _hasError = false;

  Object? failAddItemWith;
  Object? failSetQuantityWith;
  Object? failRemoveItemWith;
  Object? failClearWith;

  MockCartRepository({List<CartItemModel>? initialItems})
    : _items = {for (final i in (initialItems ?? const [])) i.id: i},
      _isLoading = false;

  @override
  bool get isLoading => _isLoading;

  @override
  bool get hasError => _hasError;

  @override
  List<CartItemModel> get items => List.unmodifiable(_items.values);

  void simulateLoading() {
    _isLoading = true;
    notifyListeners();
  }

  void simulateError() {
    _isLoading = false;
    _hasError = true;
    notifyListeners();
  }

  void simulateRecovery(List<CartItemModel> items) {
    _items
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i.id, i)));
    _isLoading = false;
    _hasError = false;
    notifyListeners();
  }

  @override
  Future<void> addItem({
    required String productId,
    int quantity = 1,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
    int priceAmountSnapshot = 0,
  }) async {
    if (failAddItemWith != null) throw failAddItemWith!;
    final draft = CartItemModel(
      productId: productId,
      quantity: quantity,
      selectedColor: selectedColor,
      selectedSize: selectedSize,
    );
    final key = draft.id;
    final existing = _items[key];
    final newQuantity = ((existing?.quantity ?? 0) + quantity).clamp(
      cartMinQuantity,
      cartMaxQuantity,
    );
    _items[key] = draft.copyWith(quantity: newQuantity);
    notifyListeners();
  }

  @override
  Future<void> setQuantity({
    required String productId,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
    required int quantity,
  }) async {
    if (failSetQuantityWith != null) throw failSetQuantityWith!;
    if (quantity < cartMinQuantity) return;
    final key = CartItemModel(
      productId: productId,
      selectedColor: selectedColor,
      selectedSize: selectedSize,
    ).id;
    final existing = _items[key];
    if (existing == null) return;
    _items[key] = existing.copyWith(
      quantity: quantity.clamp(cartMinQuantity, cartMaxQuantity),
    );
    notifyListeners();
  }

  @override
  Future<void> removeItem({
    required String productId,
    ProductColorOption? selectedColor,
    ProductSize? selectedSize,
  }) async {
    if (failRemoveItemWith != null) throw failRemoveItemWith!;
    final key = CartItemModel(
      productId: productId,
      selectedColor: selectedColor,
      selectedSize: selectedSize,
    ).id;
    _items.remove(key);
    notifyListeners();
  }

  @override
  Future<void> clear() async {
    if (failClearWith != null) throw failClearWith!;
    _items.clear();
    notifyListeners();
  }

  @visibleForTesting
  void debugSetItems(List<CartItemModel> items) {
    _items
      ..clear()
      ..addEntries(items.map((i) => MapEntry(i.id, i)));
    notifyListeners();
  }
}
