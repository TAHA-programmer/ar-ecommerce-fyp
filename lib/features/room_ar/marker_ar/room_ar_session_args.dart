import 'package:flutter/material.dart';

import '../../../core/models/product/product_ar_metadata.dart';
import 'models/marker_ar_object.dart';

/// The arguments for the customer Room-AR session route
/// ([RouteNames.roomArSession]) — a single eligible product plus the exact
/// renderable AR contract read from its live Firestore document.
///
/// Built by [RoomArPreparationViewModel] only when
/// `ProductDetailModel.hasRenderableArModel` is true for the product *and*
/// its `arMetadata.storagePath` genuinely belongs to that same product id
/// ([ProductArMetadata.belongsToProduct]). The route refuses to launch
/// without a well-formed instance, so an ineligible product never opens
/// either tier's screen.
///
/// [firestoreProductId] — not [object] — is the source of truth for product
/// identity. [object] is populated only for the four originally-bundled
/// products (chair/table/lamp/sofa); it is `null` for every other eligible
/// product (the Phase 9.2 coverage-expansion ids, and any future
/// Admin-created Room-AR product) because those have no compiled-in bundled
/// asset or bespoke native rendering treatment — they render purely from the
/// Storage-delivered GLB named by [metadata].
class RoomArSessionArgs {
  const RoomArSessionArgs({
    required this.firestoreProductId,
    required this.object,
    required this.metadata,
    required this.productTitle,
  });

  /// The live Firestore `products/{id}` document id — always present,
  /// always the key used for Storage delivery/caching.
  final String firestoreProductId;

  /// Non-null only for one of the four originally-bundled products. Purely a
  /// rendering hint (native bundled-asset slot / legacy dimension fallback /
  /// debug tooling) — never used to gate eligibility.
  final MarkerArObject? object;

  /// The verified model contract from the product's live Firestore document
  /// (storage path + SHA-256 + bounding box). Passed straight to
  /// [RoomArModelService.resolve].
  final ProductArMetadata metadata;

  /// The product's customer-facing title, shown in the AR chrome.
  final String productTitle;

  /// The native renderer's mode/slot key: [object]'s `mode` string
  /// (`"chair"`/`"table"`/`"lamp"`/`"sofa"`) for one of the four originally-
  /// bundled products — unchanged bundled-asset and shadow rendering — or
  /// this product's own [firestoreProductId] for every other product. Either
  /// way the key is unique per product and always falls through the native
  /// renderer's safe "no bundled asset, external file required" path for
  /// anything but the original four.
  String get nativeMode => object?.mode ?? firestoreProductId;

  /// Chrome icon: the bundled product's icon for the original four, a
  /// generic Room-AR glyph for everything else. [productTitle] — not this
  /// icon — is what actually identifies the product to the customer.
  IconData get displayIcon => object?.icon ?? Icons.view_in_ar_outlined;
}
