/// Arguments for [RouteNames.writeReview] (Ratings/Reviews v1 Stage 7).
///
/// [productTitle] is display-only context for the write form (e.g. "Write
/// a Review for Luna Accent Chair") - every caller already has it at hand
/// (`ProductDetailModel.summary.title` on Product Details,
/// `OrderItemModel.productName` on Order Detail, a resolved
/// `ProductSummaryModel.title` on the My Reviews list), so it's passed
/// through rather than re-fetched by the write screen itself.
class WriteReviewArgs {
  final String productId;
  final String productTitle;

  const WriteReviewArgs({required this.productId, required this.productTitle});
}
