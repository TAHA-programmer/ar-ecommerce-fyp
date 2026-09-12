import 'product_ar_metadata.dart';
import 'product_category.dart';
import 'product_color_option.dart';
import 'product_experience_type.dart';
import 'product_size.dart';
import 'product_specification.dart';
import 'product_vto_metadata.dart';
import 'product_vto_model_type.dart';
import 'product_image_ref.dart';
import 'product_publication_status.dart';

class ProductModel {
  final String id;
  final String sku;
  final String title;
  final String description;
  final String categoryId;
  final ProductCategory categoryKind;
  final String subcategory;

  final int priceAmount;
  final int? originalPriceAmount;

  final int stockQuantity;

  /// Server-resolved timestamp of the most recent stock-changing inventory
  /// operation (Phase 8.11). `null` for any product that has never had a
  /// stock update since the field was introduced - a valid state, rendered
  /// as the existing "Last updated: —" empty state, never backfilled.
  ///
  /// Owned exclusively by [CommerceDatabase.updateStock]. Every other write
  /// path (Admin product-form save, AR & Media save) must carry an existing
  /// value through unchanged and must never stamp or erase it - see
  /// `product_firestore_mapper.dart` (`toFirestoreMap` omits the key when
  /// null so a full `.set()` cannot null-out a live value) and
  /// `AdminProductFormViewModel._buildModelForSave` (preserves
  /// `_originalProduct`'s value on every edit).
  final DateTime? lastStockUpdatedAt;

  final bool isActive;
  final bool showInCatalog;
  final ProductPublicationStatus publicationStatus;

  final ProductImageRef mainImage;
  final List<ProductImageRef> galleryMedia;

  final ProductExperienceType experienceType;
  final ProductVtoModelType? vtoModelType;

  final Set<ProductColorOption> availableColors;
  final Set<ProductSize> availableSizes;
  final ProductColorOption? defaultColor;
  final ProductSize? defaultSize;
  final List<ProductSpecification> specifications;
  final String deliveryEstimate;
  final String? warranty;

  final int recommendationRank;
  final int popularityScore;
  final DateTime addedDate;
  final double rating;
  final int reviewCount;

  /// Phase 9.3 — "Dynamic Home Content" Stage 2. Explicit Admin "feature this
  /// on Home" control (replaces the overloaded `recommendationRank == 10`
  /// sentinel Home used as an interim signal). Absent/false for every product
  /// the Admin has never featured — the mapper only writes the key when it is
  /// `true`, so no existing document or seed is disturbed. Home does NOT read
  /// this until Stage 3.
  final bool isFeatured;

  /// Ordering weight for [isFeatured] products (lower = earlier). Ignored
  /// entirely when [isFeatured] is `false`; the mapper only persists it
  /// alongside a `true` [isFeatured]. Defaults to [defaultFeaturedRank].
  final int featuredRank;

  /// The neutral default [featuredRank] — a product featured without an
  /// explicit rank sorts after every explicitly-ranked one but before the
  /// non-featured tail.
  static const int defaultFeaturedRank = 1000;

  /// **Legacy Admin AR & Media staging field** — a bare asset file name chosen
  /// in the mock admin flow. It is *not* the production Room-AR pointer; the
  /// runtime uses [arMetadata] (Phase 9.2 R11/R12). Kept read/write only so the
  /// physically-approved Admin AR & Media screen does not regress; it will be
  /// migrated onto [arMetadata] in R16.
  final String? arModelAssetPath;

  /// Uniform AR scale correction (default 1.0). When [arMetadata] is present it
  /// carries the authoritative scale; this standalone field is the pre-R16
  /// Admin AR & Media mirror and stays for that screen.
  final double? arScale;

  /// The production Room-AR model contract (Phase 9.2 R11/R12): Storage object
  /// path + format + version + SHA-256 + real W/D/H metres + scale-contract id.
  /// `null` for any product with no AR model (the normal case today — no seed
  /// carries it yet; it is written per-product in R13/R14/R15).
  final ProductArMetadata? arMetadata;

  /// Phase 9.2 R16 — the admin has switched the customer Room-AR entry point
  /// **off** for this product while deliberately keeping [arMetadata] intact
  /// (so the model is recoverable with a single toggle, never re-uploaded).
  /// Distinct from *deleting* the model (which clears [arMetadata] and its
  /// Storage object) and from the product simply not opting into Room AR
  /// (`experienceType != roomAr`). Absent/false for every product that has
  /// never been touched by the R16 admin flow — the mapper only writes the key
  /// when it is `true`, so no existing document or seed is disturbed.
  final bool arModelDisabled;

  /// **Legacy Admin AR & Media staging field for Virtual Try-On** — a bare
  /// garment file name chosen in the pre-9.3 mock admin flow. It is *not* the
  /// production VTO pointer; the production contract is [vtoMetadata] (Phase
  /// 9.3 Stage 2). Kept read/write only for backward compatibility with
  /// existing documents — no production path writes it any more, exactly like
  /// [arModelAssetPath].
  final String? vtoGarmentAssetPath;

  /// The production Virtual Try-On asset contract (Phase 9.3 Stage 2): garment
  /// category + one garment reference image per colour (+ an optional
  /// product-wide default), each with a Storage object path + SHA-256 +
  /// content type + pixel size + version. `null` for every product with no
  /// try-on config — the normal case today (no seed carries it; the Admin flow
  /// that writes it is Phase 9.3 Stage 3). A present-but-incomplete config
  /// parses as a non-renderable object so admin/diagnostics can see and fix it.
  final ProductVtoMetadata? vtoMetadata;

  /// Phase 9.3 Stage 2 — the admin has switched the customer Virtual Try-On
  /// entry point **off** for this product while deliberately keeping
  /// [vtoMetadata] intact (recoverable with one toggle, never re-uploaded).
  /// Exact mirror of [arModelDisabled]: distinct from *deleting* the config
  /// (which clears [vtoMetadata]) and from the product not opting into VTO
  /// (`experienceType != virtualTryOn`). Absent/false for every product never
  /// touched by the Stage 3 admin flow — the mapper only writes the key when
  /// `true`, so no existing document or seed is disturbed.
  final bool vtoDisabled;

  const ProductModel({
    required this.id,
    required this.sku,
    required this.title,
    required this.description,
    required this.categoryId,
    required this.categoryKind,
    required this.subcategory,
    required this.priceAmount,
    this.originalPriceAmount,
    required this.stockQuantity,
    this.lastStockUpdatedAt,
    this.isActive = true,
    this.showInCatalog = true,
    this.publicationStatus = ProductPublicationStatus.published,
    required this.mainImage,
    this.galleryMedia = const [],
    required this.experienceType,
    this.vtoModelType,
    this.availableColors = const {},
    this.availableSizes = const {},
    this.defaultColor,
    this.defaultSize,
    this.specifications = const [],
    required this.deliveryEstimate,
    this.warranty,
    this.recommendationRank = 0,
    this.popularityScore = 0,
    required this.addedDate,
    this.rating = 0.0,
    this.reviewCount = 0,
    this.isFeatured = false,
    this.featuredRank = defaultFeaturedRank,
    this.arModelAssetPath,
    this.arScale,
    this.arMetadata,
    this.arModelDisabled = false,
    this.vtoGarmentAssetPath,
    this.vtoMetadata,
    this.vtoDisabled = false,
  });

  bool get inStock => stockQuantity > 0;
  bool get isRoomArEnabled => experienceType == ProductExperienceType.roomAr;
  bool get isVirtualTryOnEnabled =>
      experienceType == ProductExperienceType.virtualTryOn;

  /// `true` only when this product both opts into Room AR *and* has a fully
  /// valid, renderable model contract, *and* the admin has not switched the
  /// customer entry point off ([arModelDisabled]). Use this to gate a customer
  /// "View in Room" launch (R15/R17) — never `isRoomArEnabled` alone.
  bool get hasRenderableArModel =>
      isRoomArEnabled &&
      !arModelDisabled &&
      (arMetadata?.isRenderable ?? false);

  /// `true` when a valid model contract exists but the admin has switched the
  /// customer entry point off — the model is retained and one toggle away from
  /// live again (Phase 9.2 R16). Purely an admin-diagnostic distinction.
  bool get hasDisabledArModel =>
      isRoomArEnabled && arModelDisabled && (arMetadata?.isRenderable ?? false);

  /// `true` only when this product opts into Virtual Try-On *and* has a fully
  /// valid try-on config *and* the admin has not switched the customer entry
  /// point off *and* **at least one** colour the product actually sells
  /// resolves to a renderable garment asset (its own, or the product-wide
  /// default). Use this to gate every customer-facing try-on signal — the
  /// "Try It On" launch (Phase 9.3 Stage 5), the TRY-ON badge, and Home/
  /// Explore try-on discoverability (Stage 6) — never [isVirtualTryOnEnabled]
  /// alone.
  ///
  /// **Product-level vs per-colour:** this is deliberately an "at least one"
  /// gate, not "every colour" — a product can be genuinely try-on-ready (and
  /// advertised as such) while some of its colours have no photographed
  /// garment yet. The setup screen's own per-colour
  /// [ProductVtoMetadata.resolveGarment] check is what marks an individual
  /// uncovered colour "No preview" and disables just that selection; it is
  /// never hidden from the colour picker (a colour can still be a valid
  /// purchase choice even with no try-on preview). Folding "every colour" into
  /// this getter would make the *whole product* invisible over one missing
  /// photo, which is stricter than the UI actually needs or the customer
  /// experience calls for.
  ///
  /// It still folds in `assetsBelongToProduct` (via
  /// [ProductVtoMetadata.isRenderableForProduct]) so a well-formed but
  /// cross-product Storage path can never look launchable — Room AR keeps
  /// that ownership check as a *separate* defence layer in its preparation
  /// view-model; VTO fails closed here by default.
  bool get hasRenderableVtoAsset {
    final vto = vtoMetadata;
    if (!isVirtualTryOnEnabled || vto == null || vtoDisabled) return false;
    if (!vto.isRenderableForProduct(id)) return false;
    if (availableColors.isEmpty) return vto.garmentDefault != null;
    return availableColors.any((c) => vto.resolveGarment(c.name) != null);
  }

  /// `true` when a valid try-on config that belongs to this product exists but
  /// the admin has switched the customer entry point off — retained, one toggle
  /// from live (Stage 2 mirror of [hasDisabledArModel]). Admin-diagnostic only.
  /// Does not require per-colour coverage — it describes the *config*, not
  /// launch-readiness — but does require the paths to be this product's, so a
  /// cross-product config reads as broken rather than "disabled".
  bool get hasDisabledVtoAsset =>
      isVirtualTryOnEnabled &&
      vtoDisabled &&
      (vtoMetadata?.isRenderableForProduct(id) ?? false);

  /// The garment reference asset that would be used for [color] (its dedicated
  /// asset, or the product-wide default). `null` when the product has no
  /// try-on config or nothing resolves for that colour. Read-only helper for
  /// the later customer flow / admin preview — no side effects.
  VtoGarmentAsset? vtoGarmentForColor(ProductColorOption? color) =>
      vtoMetadata?.resolveGarment(color?.name);

  ProductModel copyWith({
    String? id,
    String? sku,
    String? title,
    String? description,
    String? categoryId,
    ProductCategory? categoryKind,
    String? subcategory,
    int? priceAmount,
    int? originalPriceAmount,
    int? stockQuantity,
    DateTime? lastStockUpdatedAt,
    bool? isActive,
    bool? showInCatalog,
    ProductPublicationStatus? publicationStatus,
    ProductImageRef? mainImage,
    List<ProductImageRef>? galleryMedia,
    ProductExperienceType? experienceType,
    ProductVtoModelType? vtoModelType,
    Set<ProductColorOption>? availableColors,
    Set<ProductSize>? availableSizes,
    ProductColorOption? defaultColor,
    ProductSize? defaultSize,
    List<ProductSpecification>? specifications,
    String? deliveryEstimate,
    String? warranty,
    int? recommendationRank,
    int? popularityScore,
    DateTime? addedDate,
    double? rating,
    int? reviewCount,
    bool? isFeatured,
    int? featuredRank,
    String? arModelAssetPath,
    double? arScale,
    ProductArMetadata? arMetadata,
    bool? arModelDisabled,
    String? vtoGarmentAssetPath,
    ProductVtoMetadata? vtoMetadata,
    bool? vtoDisabled,
    bool clearArModelAssetPath = false,
    bool clearArScale = false,
    bool clearArMetadata = false,
    bool clearVtoGarmentAssetPath = false,
    bool clearVtoModelType = false,
    bool clearVtoMetadata = false,
  }) {
    return ProductModel(
      id: id ?? this.id,
      sku: sku ?? this.sku,
      title: title ?? this.title,
      description: description ?? this.description,
      categoryId: categoryId ?? this.categoryId,
      categoryKind: categoryKind ?? this.categoryKind,
      subcategory: subcategory ?? this.subcategory,
      priceAmount: priceAmount ?? this.priceAmount,
      originalPriceAmount: originalPriceAmount ?? this.originalPriceAmount,
      stockQuantity: stockQuantity ?? this.stockQuantity,
      lastStockUpdatedAt: lastStockUpdatedAt ?? this.lastStockUpdatedAt,
      isActive: isActive ?? this.isActive,
      showInCatalog: showInCatalog ?? this.showInCatalog,
      publicationStatus: publicationStatus ?? this.publicationStatus,
      mainImage: mainImage ?? this.mainImage,
      galleryMedia: galleryMedia ?? this.galleryMedia,
      experienceType: experienceType ?? this.experienceType,
      vtoModelType: clearVtoModelType
          ? null
          : (vtoModelType ?? this.vtoModelType),
      availableColors: availableColors ?? this.availableColors,
      availableSizes: availableSizes ?? this.availableSizes,
      defaultColor: defaultColor ?? this.defaultColor,
      defaultSize: defaultSize ?? this.defaultSize,
      specifications: specifications ?? this.specifications,
      deliveryEstimate: deliveryEstimate ?? this.deliveryEstimate,
      warranty: warranty ?? this.warranty,
      recommendationRank: recommendationRank ?? this.recommendationRank,
      popularityScore: popularityScore ?? this.popularityScore,
      addedDate: addedDate ?? this.addedDate,
      rating: rating ?? this.rating,
      reviewCount: reviewCount ?? this.reviewCount,
      isFeatured: isFeatured ?? this.isFeatured,
      featuredRank: featuredRank ?? this.featuredRank,
      arModelAssetPath: clearArModelAssetPath
          ? null
          : (arModelAssetPath ?? this.arModelAssetPath),
      arScale: clearArScale ? null : (arScale ?? this.arScale),
      arMetadata: clearArMetadata ? null : (arMetadata ?? this.arMetadata),
      // Deleting the model contract clears the "entry point off" flag with it —
      // a disabled state only means something while a model is retained.
      arModelDisabled: clearArMetadata
          ? false
          : (arModelDisabled ?? this.arModelDisabled),
      vtoGarmentAssetPath: clearVtoGarmentAssetPath
          ? null
          : (vtoGarmentAssetPath ?? this.vtoGarmentAssetPath),
      vtoMetadata: clearVtoMetadata ? null : (vtoMetadata ?? this.vtoMetadata),
      // Deleting the try-on config clears the "entry point off" flag with it —
      // a disabled state only means something while a config is retained
      // (exact mirror of the arMetadata / arModelDisabled rule above).
      vtoDisabled: clearVtoMetadata ? false : (vtoDisabled ?? this.vtoDisabled),
    );
  }
}
