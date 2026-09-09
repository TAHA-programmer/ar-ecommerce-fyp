// ignore_for_file: prefer_initializing_formals
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/data/cart_repository.dart' show cartMaxQuantity;
import '../../../core/data/category_repository.dart';
import '../../../core/models/product/product_category.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';
import '../models/product_detail_model.dart';
import '../repositories/product_details_repository.dart';
import '../repositories/recently_viewed_repository.dart';

class ProductDetailsViewModel extends ChangeNotifier {
  final ProductDetailsRepository _repository;
  final CustomerShoppingState _shoppingState;
  final CategoryRepository _categoryRepository;

  /// Phase 9.3 Stage 2 — optional; when provided, a successful load of an
  /// eligible product records a view (fire-and-forget, non-blocking). Null in
  /// tests that don't care about history.
  final RecentlyViewedRepository? _recentlyViewed;
  final String productId;

  ProductDetailsViewModel({
    required ProductDetailsRepository repository,
    required CustomerShoppingState shoppingState,
    required CategoryRepository categoryRepository,
    required this.productId,
    RecentlyViewedRepository? recentlyViewed,
  }) : _repository = repository,
       _shoppingState = shoppingState,
       _categoryRepository = categoryRepository,
       _recentlyViewed = recentlyViewed {
    _loadProduct();
    _shoppingState.addListener(_onShoppingStateChanged);
  }

  void _onShoppingStateChanged() {
    notifyListeners();
  }

  @override
  void dispose() {
    _shoppingState.removeListener(_onShoppingStateChanged);
    super.dispose();
  }

  ProductDetailModel? _product;
  ProductDetailModel? get product => _product;

  bool _isLoading = true;
  bool get isLoading => _isLoading;

  String? _error;
  String? get error => _error;

  // Transient State
  int _activeGalleryIndex = 0;
  int get activeGalleryIndex => _activeGalleryIndex;

  ProductColorOption? _selectedColor;
  ProductColorOption? get selectedColor => _selectedColor;

  ProductSize? _selectedSize;
  ProductSize? get selectedSize => _selectedSize;

  int _selectedQuantity = 1;
  int get selectedQuantity => _selectedQuantity;

  // --- Stock (Phase 8.11a) ---

  /// Exact current stock from the loaded Firestore-backed product, or `0`
  /// while the product is still loading / failed to load.
  int get availableStock => _product?.stockQuantity ?? 0;

  /// True once the product is loaded and its stock is `0`. While the product
  /// is still loading this is `false` (the UI shows a spinner, not the CTA).
  bool get isOutOfStock => _product != null && _product!.stockQuantity <= 0;

  /// The largest quantity the customer may select. Capped at the available
  /// stock (and the global cart maximum). While the product hasn't loaded
  /// yet the cap is unknown, so the global maximum applies - the real guard
  /// runs in [addToCart] and at the cart/checkout gates.
  int get maxSelectableQuantity {
    if (_product == null) return cartMaxQuantity;
    if (_product!.stockQuantity <= 0) return 1;
    return math.min(_product!.stockQuantity, cartMaxQuantity);
  }

  bool get canIncrementQuantity => _selectedQuantity < maxSelectableQuantity;

  // Proxy Shopping State
  bool get isFavorite => _shoppingState.isFavorite(productId);

  /// Returns `null` on success or a clean, `AppToast`-ready error message.
  Future<String?> toggleFavorite() => _shoppingState.toggleFavorite(productId);

  /// The product's category name for display - resolves the real,
  /// live category name via [CategoryRepository] when possible, falling
  /// back to the denormalized `categoryKind.label` (e.g. "Furniture") when
  /// the category can't be resolved in this session (inactive category on a
  /// customer session, deleted category, or the repository still
  /// loading/erroring). See Phase 8.8b's category-name display decision.
  String get categoryDisplayName {
    final product = _product;
    if (product == null) return '';
    return _categoryRepository.byId(product.categoryId)?.name ??
        product.categoryKind.label;
  }

  Future<void> _loadProduct() async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      _product = await _repository.getProductDetails(productId);

      // Phase 9.3 Stage 2 — record the view. For a customer, a successful
      // single-doc read implies the product is published + active (the
      // Firestore rule denies drafts/inactive), so "load succeeded" is the
      // eligibility gate. Fire-and-forget: the repository never throws and
      // this is not awaited into the render path.
      if (_product != null) {
        _recentlyViewed?.recordView(productId);
      }

      // Initialize defaults based on available options
      if (_product != null) {
        _selectedColor =
            _product!.defaultColor ??
            (_product!.availableColors.isNotEmpty
                ? _product!.availableColors.first
                : null);
        _selectedSize =
            _product!.defaultSize ??
            (_product!.availableSizes.isNotEmpty
                ? _product!.availableSizes.first
                : null);
        // A refresh may have reduced stock below the current selection -
        // clamp it back into range so the quantity control never shows a
        // value the customer can't actually order.
        _selectedQuantity = _selectedQuantity.clamp(1, maxSelectableQuantity);
      }
    } catch (e) {
      _error = 'Failed to load product details. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    await _loadProduct();
  }

  void setActiveGalleryIndex(int index) {
    if (_activeGalleryIndex != index) {
      _activeGalleryIndex = index;
      notifyListeners();
    }
  }

  void selectColor(ProductColorOption color) {
    if (_selectedColor != color) {
      _selectedColor = color;
      notifyListeners();
    }
  }

  void selectSize(ProductSize size) {
    if (_selectedSize != size) {
      _selectedSize = size;
      notifyListeners();
    }
  }

  /// Increments the selected quantity. Returns `null` on success, or a
  /// clean, `AppToast`-ready message when the available-stock limit has been
  /// reached (the value is left unchanged in that case).
  String? incrementQuantity() {
    if (!canIncrementQuantity) {
      if (isOutOfStock) return 'This product is out of stock.';
      return 'Only $availableStock available.';
    }
    _selectedQuantity++;
    notifyListeners();
    return null;
  }

  void decrementQuantity() {
    if (_selectedQuantity > 1) {
      _selectedQuantity--;
      notifyListeners();
    }
  }

  /// Returns `null` on success or a clean, `AppToast`-ready error message.
  ///
  /// Business-logic guard (Phase 8.11a): even if the UI somehow lets it
  /// through, an out-of-stock product can never be added, and the quantity
  /// can never exceed the loaded product's current stock. This is a
  /// best-effort local check against possibly-stale data - the Cart's
  /// pre-checkout validation and Phase 8.13's server reservation are the
  /// authoritative gates.
  Future<String?> addToCart() {
    final product = _product;
    if (product != null) {
      if (product.stockQuantity <= 0) {
        return Future.value('This product is out of stock.');
      }
      if (_selectedQuantity > product.stockQuantity) {
        return Future.value('Only ${product.stockQuantity} available.');
      }
    }
    final priceStr = (_product?.summary.currentPrice ?? '').replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return _shoppingState.addToCart(
      productId,
      quantity: _selectedQuantity,
      selectedColor: _selectedColor,
      selectedSize: _selectedSize,
      priceAmountSnapshot: int.tryParse(priceStr) ?? 0,
    );
  }
}
