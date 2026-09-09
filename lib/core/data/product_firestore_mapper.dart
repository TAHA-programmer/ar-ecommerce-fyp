import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/product/product_ar_metadata.dart';
import '../models/product/product_category.dart';
import '../models/product/product_color_option.dart';
import '../models/product/product_experience_type.dart';
import '../models/product/product_image_ref.dart';
import '../models/product/product_model.dart';
import '../models/product/product_publication_status.dart';
import '../models/product/product_size.dart';
import '../models/product/product_specification.dart';
import '../models/product/product_vto_model_type.dart';

// Firestore <-> ProductModel mapping for `products/{productId}`.
//
// Shared by every Firestore-backed reader this phase
// (FirestoreCommerceDatabase and the Home/Explore/Product Details Firestore
// repositories) and by the developer-only seed export tool
// (`tool/export_product_seed.dart`), so the schema is defined exactly once.
// ProductModel itself stays Firestore-free - only this file knows about the
// wire format.

/// Read direction: a Firestore `products/{id}` document -> [ProductModel].
/// Unknown/missing/malformed fields fall back to safe defaults rather than
/// throwing, mirroring [FirestoreUserProfileRepository]'s mapping style -
/// this data is only ever written by our own seed tooling (Phase 8.5) or a
/// future Admin write path (Phase 8.6), never by an untrusted client.
ProductModel productModelFromFirestore(String id, Map<String, dynamic> data) {
  return ProductModel(
    id: id,
    sku: data['sku'] as String? ?? '',
    title: data['title'] as String? ?? '',
    description: data['description'] as String? ?? '',
    categoryId: _categoryIdFromData(data),
    categoryKind: _categoryKindFromData(data),
    subcategory: data['subcategory'] as String? ?? '',
    priceAmount: (data['priceAmount'] as num?)?.toInt() ?? 0,
    originalPriceAmount: (data['originalPriceAmount'] as num?)?.toInt(),
    stockQuantity: (data['stockQuantity'] as num?)?.toInt() ?? 0,
    lastStockUpdatedAt: _nullableDateFromTimestamp(data['lastStockUpdatedAt']),
    isActive: data['isActive'] as bool? ?? true,
    showInCatalog: data['showInCatalog'] as bool? ?? true,
    publicationStatus: _publicationStatusFromName(
      data['publicationStatus'] as String?,
    ),
    mainImage: _imageRefFromMap(data['mainImage'] as Map<String, dynamic>?),
    galleryMedia: (data['galleryMedia'] as List<dynamic>? ?? const [])
        .map((e) => _imageRefFromMap(e as Map<String, dynamic>?))
        .toList(),
    experienceType: _experienceTypeFromName(data['experienceType'] as String?),
    vtoModelType: _vtoModelTypeFromName(data['vtoModelType'] as String?),
    availableColors: (data['availableColors'] as List<dynamic>? ?? const [])
        .map((e) => _colorFromName(e as String?))
        .whereType<ProductColorOption>()
        .toSet(),
    availableSizes: (data['availableSizes'] as List<dynamic>? ?? const [])
        .map((e) => _sizeFromName(e as String?))
        .whereType<ProductSize>()
        .toSet(),
    defaultColor: _colorFromName(data['defaultColor'] as String?),
    defaultSize: _sizeFromName(data['defaultSize'] as String?),
    specifications: (data['specifications'] as List<dynamic>? ?? const []).map((
      e,
    ) {
      final map = e as Map<String, dynamic>;
      return ProductSpecification(
        label: map['label'] as String? ?? '',
        value: map['value'] as String? ?? '',
      );
    }).toList(),
    deliveryEstimate: data['deliveryEstimate'] as String? ?? '',
    warranty: data['warranty'] as String?,
    recommendationRank: (data['recommendationRank'] as num?)?.toInt() ?? 0,
    popularityScore: (data['popularityScore'] as num?)?.toInt() ?? 0,
    addedDate: _dateFromTimestamp(data['addedDate']),
    rating: (data['rating'] as num?)?.toDouble() ?? 0.0,
    reviewCount: (data['reviewCount'] as num?)?.toInt() ?? 0,
    // Phase 9.3 "Dynamic Home Content" Stage 2 — explicit Admin feature flag.
    // Absent on every pre-Stage-2 document => `false` / the neutral rank.
    isFeatured: data['isFeatured'] as bool? ?? false,
    featuredRank:
        (data['featuredRank'] as num?)?.toInt() ??
        ProductModel.defaultFeaturedRank,
    // Legacy Admin AR & Media staging fields (kept until R16).
    arModelAssetPath: data['arModelAssetPath'] as String?,
    arScale: (data['arScale'] as num?)?.toDouble(),
    // Phase 9.2 R11/R12 production Room-AR contract. `null` when the doc has no
    // `arModelStoragePath`; a present-but-broken contract still parses (as a
    // non-renderable object) so admin/diagnostics can see and fix it.
    arMetadata: ProductArMetadata.fromProductData(data),
    // Phase 9.2 R16 — admin has switched the customer Room-AR entry point off
    // while keeping the model. Absent on every pre-R16 document => `false`.
    arModelDisabled: data['arModelDisabled'] as bool? ?? false,
    vtoGarmentAssetPath: data['vtoGarmentAssetPath'] as String?,
  );
}

extension ProductModelFirestoreMapper on ProductModel {
  /// Write direction: [ProductModel] -> a Firestore-ready map. Only used by
  /// the developer-only seed export tool this phase
  /// (`tool/export_product_seed.dart`) - the app itself does not write
  /// products to Firestore until Phase 8.6.
  Map<String, dynamic> toFirestoreMap() {
    final stockStamp = lastStockUpdatedAt;
    final map = <String, dynamic>{
      'sku': sku,
      'title': title,
      'description': description,
      'categoryId': categoryId,
      'categoryKind': categoryKind.name,
      'subcategory': subcategory,
      'priceAmount': priceAmount,
      'originalPriceAmount': originalPriceAmount,
      'stockQuantity': stockQuantity,
      // Phase 8.11: only written when non-null. A full-document `.set()`
      // (addProduct/updateProduct) would otherwise persist an explicit
      // `null` and erase a live server timestamp on the next Admin edit;
      // omitting the key leaves an existing value untouched on a merge and
      // reads back as `null` for a genuinely new product. The
      // stock-changing path (CommerceDatabase.updateStock) writes its own
      // `FieldValue.serverTimestamp()` directly and never goes through here.
      if (stockStamp != null)
        'lastStockUpdatedAt': Timestamp.fromDate(stockStamp),
      'isActive': isActive,
      'showInCatalog': showInCatalog,
      'publicationStatus': publicationStatus.name,
      'mainImage': _imageRefToMap(mainImage),
      'galleryMedia': galleryMedia.map(_imageRefToMap).toList(),
      'experienceType': experienceType.name,
      'vtoModelType': vtoModelType?.name,
      'availableColors': availableColors.map((c) => c.name).toList(),
      'availableSizes': availableSizes.map((s) => s.name).toList(),
      'defaultColor': defaultColor?.name,
      'defaultSize': defaultSize?.name,
      'specifications': specifications
          .map((s) => {'label': s.label, 'value': s.value})
          .toList(),
      'deliveryEstimate': deliveryEstimate,
      'warranty': warranty,
      'recommendationRank': recommendationRank,
      'popularityScore': popularityScore,
      'addedDate': Timestamp.fromDate(addedDate),
      'rating': rating,
      'reviewCount': reviewCount,
      // Phase 9.3 Stage 2: only persisted when the product is actually
      // featured — same "omit when default" discipline as `arModelDisabled`
      // and `lastStockUpdatedAt`, so a full `.set()` never adds noise keys
      // to an untouched product or churns the seed export.
      if (isFeatured) 'isFeatured': true,
      if (isFeatured) 'featuredRank': featuredRank,
      // Legacy Admin AR & Media staging fields (kept until R16).
      'arModelAssetPath': arModelAssetPath,
      'arScale': arScale,
      'vtoGarmentAssetPath': vtoGarmentAssetPath,
    };
    // Phase 9.2 R11/R12: when the product has a production Room-AR contract,
    // write its flat `ar*` fields. This also supplies the authoritative
    // `arScale`, overriding the legacy mirror above. Omitted entirely when
    // `arMetadata == null`, so existing/non-AR documents are unaffected.
    final ar = arMetadata;
    if (ar != null) map.addAll(ar.toFirestoreFields());
    // Phase 9.2 R16: only written when the admin has actually turned the
    // customer entry point off — same "omit when false" discipline as
    // `lastStockUpdatedAt`, so a full `.set()` never adds a noise key to an
    // untouched product or churns the seed export.
    if (arModelDisabled) map['arModelDisabled'] = true;
    return map;
  }
}

Map<String, dynamic> _imageRefToMap(ProductImageRef ref) => {
  'path': ref.path,
  'source': ref.source.name,
  'altText': ref.altText,
};

ProductImageRef _imageRefFromMap(Map<String, dynamic>? map) {
  if (map == null) return const ProductImageRef(path: '');
  return ProductImageRef(
    path: map['path'] as String? ?? '',
    source: _imageSourceFromName(map['source'] as String?),
    altText: map['altText'] as String? ?? '',
  );
}

DateTime _dateFromTimestamp(Object? value) {
  if (value is Timestamp) return value.toDate();
  return DateTime.fromMillisecondsSinceEpoch(0);
}

/// Like [_dateFromTimestamp] but returns `null` for an absent/pending/
/// malformed value instead of the epoch sentinel - used for
/// `lastStockUpdatedAt` (Phase 8.11), where "never updated" is a real,
/// displayable state and must never be confused with 1970. A
/// `FieldValue.serverTimestamp()` write can also momentarily echo back as
/// `null` before the server resolves it; callers treat that the same as
/// "not yet updated" until the next snapshot carries the real value.
DateTime? _nullableDateFromTimestamp(Object? value) {
  if (value is Timestamp) return value.toDate();
  return null;
}

/// Phase 8.8b dual-read: prefers the real `categoryId` reference, falling
/// back to the legacy `category` enum-name field (still present on any
/// product a Firestore backfill/edit hasn't touched yet - see
/// `product_firestore_mapper.dart`'s doc comment at the top and the Phase
/// 8.8b migration tool). For the five originally-seeded categories,
/// `categoryId == category` (the enum name), so the legacy value is directly
/// reusable as-is, no lookup needed.
String _categoryIdFromData(Map<String, dynamic> data) =>
    data['categoryId'] as String? ?? data['category'] as String? ?? '';

/// Same dual-read as [_categoryIdFromData], for the denormalized AR/VTO
/// taxonomy field. Unknown/missing/malformed values must never silently
/// resolve to [ProductCategory.all] (a UI-only filter sentinel, never a real
/// taxonomy value) - falls back to [ProductCategory.furniture] instead,
/// exactly mirroring `category_firestore_mapper.dart`'s `_kindFromName`.
ProductCategory _categoryKindFromData(Map<String, dynamic> data) {
  final raw = data['categoryKind'] as String? ?? data['category'] as String?;
  for (final k in ProductCategory.values) {
    if (k == ProductCategory.all) continue;
    if (k.name == raw) return k;
  }
  return ProductCategory.furniture;
}

ProductPublicationStatus _publicationStatusFromName(String? name) =>
    ProductPublicationStatus.values.firstWhere(
      (s) => s.name == name,
      // Unknown/missing status must never default to visible-to-customers.
      orElse: () => ProductPublicationStatus.draft,
    );

ProductExperienceType _experienceTypeFromName(String? name) =>
    ProductExperienceType.values.firstWhere(
      (e) => e.name == name,
      orElse: () => ProductExperienceType.none,
    );

ProductVtoModelType? _vtoModelTypeFromName(String? name) {
  if (name == null) return null;
  for (final v in ProductVtoModelType.values) {
    if (v.name == name) return v;
  }
  return null;
}

ProductColorOption? _colorFromName(String? name) {
  if (name == null) return null;
  for (final c in ProductColorOption.values) {
    if (c.name == name) return c;
  }
  return null;
}

ProductSize? _sizeFromName(String? name) {
  if (name == null) return null;
  for (final s in ProductSize.values) {
    if (s.name == name) return s;
  }
  return null;
}

ProductImageSource _imageSourceFromName(String? name) =>
    ProductImageSource.values.firstWhere(
      (s) => s.name == name,
      orElse: () => ProductImageSource.network,
    );
