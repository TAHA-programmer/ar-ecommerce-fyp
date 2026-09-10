import '../../../core/models/product/product_ar_metadata.dart';
import '../../../core/models/product/product_summary_model.dart';
import '../../../core/models/product/product_category.dart';
import '../../../core/models/product/product_experience_type.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';
import '../../../core/models/product/product_image_ref.dart';
import '../../../core/models/product/product_specification.dart';
import '../../../core/models/product/product_vto_metadata.dart';
import '../../../core/models/product/product_vto_model_type.dart';

class ProductDetailModel {
  final ProductSummaryModel summary;

  /// The product's exact current stock, straight from the Firestore-backed
  /// [ProductModel.stockQuantity] (never hardcoded). `0` means out of stock.
  /// Used by Product Details for the "N available" / "Out of Stock" display
  /// and its add-to-cart / quantity guards, and by the Cart's
  /// pre-checkout stock validation. Refreshed whenever the product is
  /// re-fetched (screen re-entry / pull-to-refresh) - Product Details uses a
  /// one-shot fetch, not a realtime listener (Phase 8.5).
  final int stockQuantity;

  final String categoryId;
  final ProductCategory categoryKind;
  final ProductExperienceType experienceType;
  final ProductVtoModelType? vtoModelType;

  /// The production Room-AR model contract (Phase 9.2 R11/R12), or `null` when
  /// the product has no AR model. Carried through from [ProductModel] so the
  /// customer-facing Room-AR launch (R15/R17) reads a first-class typed
  /// contract instead of a bare asset-path string. Gate a "View in Room"
  /// action on [hasRenderableArModel], never on `experienceType` alone.
  final ProductArMetadata? arMetadata;

  /// Phase 9.2 R16 — the admin has switched the customer Room-AR entry point
  /// off while keeping [arMetadata]. `false` for every product not touched by
  /// the R16 admin flow. Folds into [hasRenderableArModel] so a disabled model
  /// never offers a customer launch.
  final bool arModelDisabled;

  /// The production Virtual Try-On asset contract (Phase 9.3 Stage 2), or
  /// `null` when the product has no try-on config. Carried through from
  /// [ProductModel] so the later customer "Try It On" launch (Stage 5) reads a
  /// first-class typed contract. Gate that launch on [hasRenderableVtoAsset],
  /// never on `experienceType` alone. Nothing reads this yet.
  final ProductVtoMetadata? vtoMetadata;

  /// Phase 9.3 Stage 2 mirror of [arModelDisabled] — the admin has switched the
  /// customer Virtual Try-On entry point off while keeping [vtoMetadata].
  /// `false` for every product not touched by the Stage 3 admin flow.
  final bool vtoDisabled;

  // Breadcrumb hierarchy
  final String subcategory; // e.g. "Accent Chairs", "Shirts"

  // Media
  final List<ProductImageRef> gallery;

  // Description
  final String description;

  // Variants
  final List<ProductColorOption> availableColors;
  final List<ProductSize> availableSizes; // Empty for furniture
  final ProductColorOption? defaultColor;
  final ProductSize? defaultSize;

  // Details
  final List<ProductSpecification> specifications;

  // Metadata
  final String deliveryEstimate; // e.g. "3-5 Business Days"
  final String? warranty; // e.g. "1 Year Manufacturer Warranty"

  const ProductDetailModel({
    required this.summary,
    required this.stockQuantity,
    required this.categoryId,
    required this.categoryKind,
    required this.experienceType,
    this.vtoModelType,
    this.arMetadata,
    this.arModelDisabled = false,
    this.vtoMetadata,
    this.vtoDisabled = false,
    required this.subcategory,
    required this.gallery,
    required this.description,
    required this.availableColors,
    required this.availableSizes,
    this.defaultColor,
    this.defaultSize,
    required this.specifications,
    required this.deliveryEstimate,
    this.warranty,
  });

  bool get isRoomArEnabled => experienceType == ProductExperienceType.roomAr;

  /// `true` only when the product opts into Room AR *and* has a fully valid,
  /// renderable model contract — the gate for a customer "View in Room" launch.
  bool get hasRenderableArModel =>
      isRoomArEnabled &&
      !arModelDisabled &&
      (arMetadata?.isRenderable ?? false);

  bool get isVirtualTryOnEnabled =>
      experienceType == ProductExperienceType.virtualTryOn;

  /// `true` only when the product opts into Virtual Try-On *and* has a fully
  /// valid config that belongs to this product (`isRenderableForProduct`) *and*
  /// the admin has not switched it off *and* every [availableColors] entry
  /// resolves to a renderable garment asset — the gate for a customer "Try It
  /// On" launch (Phase 9.3 Stage 5). Exact mirror of
  /// [ProductModel.hasRenderableVtoAsset]. Nothing reads it yet.
  bool get hasRenderableVtoAsset {
    final vto = vtoMetadata;
    if (!isVirtualTryOnEnabled || vto == null || vtoDisabled) return false;
    if (!vto.isRenderableForProduct(summary.id)) return false;
    if (availableColors.isEmpty) return vto.garmentDefault != null;
    return availableColors.every((c) => vto.resolveGarment(c.name) != null);
  }

  /// `true` when a valid try-on config that belongs to this product exists but
  /// the admin switched the entry point off — admin-diagnostic only (mirror of
  /// [ProductModel.hasDisabledVtoAsset]).
  bool get hasDisabledVtoAsset =>
      isVirtualTryOnEnabled &&
      vtoDisabled &&
      (vtoMetadata?.isRenderableForProduct(summary.id) ?? false);

  /// The garment reference asset that would be used for [color] — its dedicated
  /// asset or the product-wide default. `null` when nothing resolves.
  VtoGarmentAsset? vtoGarmentForColor(ProductColorOption? color) =>
      vtoMetadata?.resolveGarment(color?.name);
}
