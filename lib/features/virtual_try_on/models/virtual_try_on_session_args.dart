/// Arguments for [RouteNames.virtualTryOnSession] — built by
/// [VirtualTryOnSetupViewModel] once the customer taps "Start Try-On" with
/// consent given. The session screen re-loads the product itself (mirrors
/// how the setup screen only ever receives a productId); this keeps the
/// argument minimal and the product data always fresh.
class VirtualTryOnSessionArgs {
  final String productId;

  /// [ProductColorOption.name] — selects which garment asset is used.
  final String colorKey;

  /// [ProductSize.name], or `null` for a product with no sizes. A soft
  /// styling hint only — never affects which garment asset is used.
  final String? size;

  /// Minted once by the setup screen; carried through so a retry within the
  /// session screen can reuse it (same attempt) or the session screen mints
  /// a fresh one (a genuinely new attempt) as appropriate.
  final String idempotencyKey;

  const VirtualTryOnSessionArgs({
    required this.productId,
    required this.colorKey,
    this.size,
    required this.idempotencyKey,
  });
}
