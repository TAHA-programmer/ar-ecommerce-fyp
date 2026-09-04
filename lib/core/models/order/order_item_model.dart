import '../product/product_image_ref.dart';

class OrderItemModel {
  final String productId;
  final String productName;
  final String imagePath;

  /// Carries the product image's source at the moment this immutable order
  /// snapshot was taken (Phase 8.7 source-awareness fix - see
  /// `ProductSummaryModel.imageSource`'s doc comment for the same rationale).
  /// Defaults to `.asset` so every pre-8.7 test/call site constructing an
  /// `OrderItemModel` without this field keeps compiling and behaving
  /// exactly as before.
  final ProductImageSource imageSource;

  final int quantity;
  final String? selectedSize;
  final String? selectedColor;
  final double unitPrice;
  final double lineTotal;

  OrderItemModel({
    required this.productId,
    required this.productName,
    required this.imagePath,
    this.imageSource = ProductImageSource.asset,
    required this.quantity,
    this.selectedSize,
    this.selectedColor,
    required this.unitPrice,
    required this.lineTotal,
  });

  /// The full source-aware image reference - the preferred way for a
  /// rendering widget to get a [ProductImageRef] for `ProductImageView`.
  ProductImageRef get image =>
      ProductImageRef(path: imagePath, source: imageSource);
}
