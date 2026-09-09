import 'package:flutter/foundation.dart';
import '../../../core/models/product/product_experience_type.dart';
import '../../product_details/models/product_detail_model.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../capability/room_ar_capability.dart';
import '../capability/room_ar_capability_service.dart';
import '../marker_ar/models/marker_ar_object.dart';
import '../marker_ar/room_ar_session_args.dart';

/// Backs the Room-AR preparation screen (Phase 9.2 R15/R17 + R7/R8).
///
/// Loads the opened product, checks it has a fully valid, renderable
/// `arMetadata` contract that genuinely belongs to it
/// (`ProductDetailModel.hasRenderableArModel` +
/// `ProductArMetadata.belongsToProduct`), then runs the device-capability
/// probe (R8) and resolves the best **currently usable** tier: Tier-1
/// markerless ARCore (R6), Tier-2 Marker AR, the Tier-3 Interactive 3D
/// Preview, or (rare) neither. The screen adapts its copy and its launch
/// button to [resolvedTier]; ineligible products still show the honest "not
/// ready yet" state and cannot launch anything.
///
/// Eligibility is **not** limited to the four originally-bundled products —
/// see [RoomArSessionArgs] for how a product with no bundled/native-
/// specialized rendering treatment still gets its own correct model.
class RoomArPreparationViewModel extends ChangeNotifier {
  final ProductDetailsRepository repository;
  final RoomArCapabilityService capabilityService;
  final String productId;

  bool _isLoading = true;
  String? _error;
  ProductDetailModel? _product;
  RoomArTierDecision _decision = const RoomArTierDecision(
    RoomArTier.tier2Marker,
    'not-detected',
  );

  RoomArPreparationViewModel({
    required this.repository,
    required this.capabilityService,
    required this.productId,
  }) {
    _load();
  }

  bool get isLoading => _isLoading;
  String? get error => _error;
  ProductDetailModel? get product => _product;

  /// The resolved tier for this product on this device. Only meaningful once
  /// [product] is non-null and [canPreview] / [canStartAr] have been consulted.
  RoomArTier get resolvedTier => _decision.tier;
  String get tierReason => _decision.reason;

  bool get _eligible => _sessionArgs != null;

  /// Launch Tier-1 markerless ARCore (Phase 9.2 R6).
  bool get canStartArCore =>
      _eligible && _decision.tier == RoomArTier.tier1Arcore;

  /// Launch Tier-2 Marker AR.
  bool get canStartAr => _eligible && _decision.tier == RoomArTier.tier2Marker;

  /// Launch the Tier-3 Interactive 3D Preview.
  bool get canPreview => _eligible && _decision.tier == RoomArTier.tier3Preview;

  /// The product opts into Room AR + has an approved model, but this device
  /// can run neither tier (no OpenGL ES 3.0).
  bool get deviceUnsupported =>
      _eligible && _decision.tier == RoomArTier.unsupported;

  RoomArSessionArgs? get sessionArgs => _sessionArgs;

  RoomArSessionArgs? get _sessionArgs {
    final p = _product;
    if (p == null || !p.hasRenderableArModel) return null;
    final metadata = p.arMetadata;
    // Defence-in-depth: refuse a contract whose storage path doesn't
    // actually belong to this product id (see [ProductArMetadata
    // .belongsToProduct]) — never launch a session that could render a
    // different product's model.
    if (metadata == null || !metadata.belongsToProduct(p.summary.id)) {
      return null;
    }
    return RoomArSessionArgs(
      firestoreProductId: p.summary.id,
      // Non-null only for the four originally-bundled products — a pure
      // rendering hint, never an eligibility requirement (see
      // RoomArSessionArgs's doc comment).
      object: MarkerArObject.fromFirestoreProductId(p.summary.id),
      metadata: metadata,
      productTitle: p.summary.title,
    );
  }

  Future<void> _load() async {
    try {
      _isLoading = true;
      _error = null;
      notifyListeners();

      final result = await repository.getProductDetails(productId);
      if (result.experienceType != ProductExperienceType.roomAr) {
        _error = 'This product does not support Room AR.';
        _product = null;
      } else {
        _product = result;
      }
    } catch (_) {
      _error = 'Failed to load product details';
      _product = null;
    }

    // Only probe the device when the product could actually use a tier.
    if (_product?.hasRenderableArModel ?? false) {
      try {
        final caps = await capabilityService.detect();
        _decision = decideRoomArTier(caps);
      } catch (_) {
        _decision = decideRoomArTier(RoomArDeviceCapabilities.unknown);
      }
    }

    _isLoading = false;
    notifyListeners();
  }

  Future<void> retry() => _load();
}
