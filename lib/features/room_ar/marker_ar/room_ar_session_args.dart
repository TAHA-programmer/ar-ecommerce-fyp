import '../../../core/models/product/product_ar_metadata.dart';
import 'models/marker_ar_object.dart';

/// The arguments for the customer Room-AR session route
/// ([RouteNames.roomArSession]) — a single approved product plus the exact
/// renderable AR contract read from its live Firestore document.
///
/// Built by [RoomArPreparationViewModel] only when the product is one of the
/// four physically-approved Room-AR products *and* its `arMetadata` is
/// renderable ([ProductDetailModel.hasRenderableArModel]). The route refuses to
/// launch without a well-formed instance, so the Marker-AR screen never opens
/// for an ineligible product.
class RoomArSessionArgs {
  const RoomArSessionArgs({
    required this.object,
    required this.metadata,
    required this.productTitle,
  });

  /// Which of the four approved products this session renders.
  final MarkerArObject object;

  /// The verified model contract from the product's live Firestore document
  /// (storage path + SHA-256 + bounding box). Passed straight to
  /// [RoomArModelService.resolve].
  final ProductArMetadata metadata;

  /// The product's customer-facing title, shown in the AR chrome.
  final String productTitle;
}
