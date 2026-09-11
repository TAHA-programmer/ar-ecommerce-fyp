/// Arguments for [RouteNames.virtualTryOnSetup].
///
/// [initialColorKey]/[initialSize] carry the colour/size the customer already
/// had selected on Product Details ([ProductColorOption.name] /
/// [ProductSize.name]) so Virtual Try-On opens on the same variant instead of
/// silently resetting to the product's defaults. Either may be `null` (no
/// selection yet, or the product has no variants of that kind) — the setup
/// screen falls back to the product's own defaults exactly like Product
/// Details does.
class VirtualTryOnSetupArgs {
  final String productId;
  final String? initialColorKey;
  final String? initialSize;

  const VirtualTryOnSetupArgs({
    required this.productId,
    this.initialColorKey,
    this.initialSize,
  });
}
