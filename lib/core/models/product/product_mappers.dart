import 'package:intl/intl.dart';

import 'product_model.dart';
import 'product_summary_model.dart';
import '../../../../features/explore/models/catalog_product_model.dart';
import '../../../../features/product_details/models/product_detail_model.dart';

extension ProductModelMappers on ProductModel {
  String get formattedCurrentPrice {
    final formatter = NumberFormat('#,##0');
    return 'Rs ${formatter.format(priceAmount)}/-';
  }

  String? get formattedOriginalPrice {
    if (originalPriceAmount == null) return null;
    final formatter = NumberFormat('#,##0');
    return 'Rs ${formatter.format(originalPriceAmount)}/-';
  }

  String? get computedDiscountPercentage {
    if (originalPriceAmount == null || originalPriceAmount == 0) return null;
    final diff = originalPriceAmount! - priceAmount;
    if (diff <= 0) return null;
    final pct = (diff / originalPriceAmount!) * 100;
    return '${pct.round()}% OFF';
  }

  ProductSummaryModel toSummaryModel() {
    return ProductSummaryModel(
      id: id,
      title: title,
      imageAssetPath: mainImage.path,
      imageSource: mainImage.source,
      currentPrice: formattedCurrentPrice,
      originalPrice: formattedOriginalPrice,
      discountPercentage: computedDiscountPercentage,
      rating: rating,
      reviewCount: reviewCount,
      inStock: inStock,
      arEnabled: isRoomArEnabled,
      tryOnEnabled: isVirtualTryOnEnabled,
    );
  }

  CatalogProductModel toCatalogModel() {
    return CatalogProductModel(
      summary: toSummaryModel(),
      categoryId: categoryId,
      categoryKind: categoryKind,
      priceAmount: priceAmount,
      sizes: availableSizes,
      colors: availableColors,
      recommendationRank: recommendationRank,
      addedDate: addedDate,
      popularityScore: popularityScore,
    );
  }

  ProductDetailModel toDetailModel() {
    return ProductDetailModel(
      summary: toSummaryModel(),
      stockQuantity: stockQuantity,
      categoryId: categoryId,
      categoryKind: categoryKind,
      experienceType: experienceType,
      vtoModelType: vtoModelType,
      // Phase 9.2 R12: the detail model now carries the production Room-AR
      // contract (was the "current blocker" — it previously had no AR fields).
      arMetadata: arMetadata,
      // Phase 9.2 R16: a model the admin has switched off must not offer a
      // customer launch even though the contract is still valid.
      arModelDisabled: arModelDisabled,
      subcategory: subcategory,
      gallery: galleryMedia,
      description: description,
      availableColors: availableColors.toList(),
      availableSizes: availableSizes.toList(),
      defaultColor: defaultColor,
      defaultSize: defaultSize,
      specifications: specifications,
      deliveryEstimate: deliveryEstimate,
      warranty: warranty,
    );
  }
}
