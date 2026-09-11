// ignore_for_file: prefer_initializing_formals
import 'package:flutter/material.dart';

import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';
import '../../product_details/models/product_detail_model.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../services/virtual_try_on_idempotency.dart';

/// Drives the Virtual Try-On setup/consent screen (Phase 9.3 Stage 5): loads
/// the product, gates on [ProductDetailModel.hasRenderableVtoAsset], lets the
/// customer pick a colour/size (defaulting to whatever they already had
/// selected on Product Details, falling back to the product's own defaults),
/// and requires a freshly-checked consent box before "Start Try-On" is
/// enabled — re-checked every visit (D5), never persisted.
class VirtualTryOnSetupViewModel extends ChangeNotifier {
  final ProductDetailsRepository _repository;
  final String productId;
  final String? _initialColorKey;
  final String? _initialSize;

  VirtualTryOnSetupViewModel({
    required ProductDetailsRepository repository,
    required this.productId,
    String? initialColorKey,
    String? initialSize,
  }) : _repository = repository,
       _initialColorKey = initialColorKey,
       _initialSize = initialSize {
    _loadProduct();
  }

  bool isLoading = true;
  String? error;
  ProductDetailModel? product;

  ProductColorOption? selectedColor;
  ProductSize? selectedSize;
  bool consentChecked = false;

  Future<void> _loadProduct() async {
    isLoading = true;
    error = null;
    notifyListeners();

    try {
      final loaded = await _repository.getProductDetails(productId);
      product = loaded;

      if (!loaded.hasRenderableVtoAsset) {
        error = "Virtual Try-On isn't available for this product.";
      } else {
        selectedColor = _resolveInitialColor(loaded);
        selectedSize = _resolveInitialSize(loaded);
      }
    } catch (_) {
      error = 'Failed to load product details for Virtual Try-On.';
    } finally {
      isLoading = false;
      notifyListeners();
    }
  }

  /// The customer's carried-over Product Details colour, if it's still
  /// eligible for try-on preview; otherwise the product's default colour, if
  /// eligible; otherwise the first eligible colour. `null` only if the
  /// product genuinely has no colours (never reached when
  /// [ProductDetailModel.hasRenderableVtoAsset] is true, since that requires
  /// every available colour to resolve — kept defensive regardless).
  ProductColorOption? _resolveInitialColor(ProductDetailModel p) {
    final carriedOver = _colorByName(p, _initialColorKey);
    if (carriedOver != null && colorHasPreview(p, carriedOver)) {
      return carriedOver;
    }
    if (p.defaultColor != null && colorHasPreview(p, p.defaultColor!)) {
      return p.defaultColor;
    }
    for (final c in p.availableColors) {
      if (colorHasPreview(p, c)) return c;
    }
    return null;
  }

  ProductSize? _resolveInitialSize(ProductDetailModel p) {
    final carriedOver = _sizeByName(p, _initialSize);
    if (carriedOver != null) return carriedOver;
    return p.defaultSize ??
        (p.availableSizes.isNotEmpty ? p.availableSizes.first : null);
  }

  ProductColorOption? _colorByName(ProductDetailModel p, String? name) {
    if (name == null) return null;
    for (final c in p.availableColors) {
      if (c.name == name) return c;
    }
    return null;
  }

  ProductSize? _sizeByName(ProductDetailModel p, String? name) {
    if (name == null) return null;
    for (final s in p.availableSizes) {
      if (s.name == name) return s;
    }
    return null;
  }

  /// `true` when [color] resolves to a renderable garment asset — a colour
  /// with no configured asset is shown but disabled for try-on (it may still
  /// be a perfectly valid purchase colour).
  bool colorHasPreview(ProductDetailModel p, ProductColorOption color) =>
      p.vtoGarmentForColor(color) != null;

  void selectColor(ProductColorOption color) {
    final p = product;
    if (p == null || !colorHasPreview(p, color)) return;
    if (selectedColor != color) {
      selectedColor = color;
      notifyListeners();
    }
  }

  void selectSize(ProductSize size) {
    if (selectedSize != size) {
      selectedSize = size;
      notifyListeners();
    }
  }

  void setConsentChecked(bool value) {
    if (consentChecked != value) {
      consentChecked = value;
      notifyListeners();
    }
  }

  /// "Start Try-On" is enabled only once the product is genuinely eligible, a
  /// colour with a real preview asset is selected, and consent is checked.
  bool get canStart {
    final p = product;
    if (p == null || !p.hasRenderableVtoAsset) return false;
    final color = selectedColor;
    if (color == null || !colorHasPreview(p, color)) return false;
    return consentChecked;
  }

  /// Mints a fresh idempotency key for a new try-on attempt — called once,
  /// when "Start Try-On" is tapped.
  String startNewAttemptIdempotencyKey() =>
      generateVirtualTryOnIdempotencyKey();
}
