/// Where the Virtual Try-On session screen is (Phase 9.3 Stage 5).
enum VirtualTryOnSessionPhase {
  /// No photo chosen yet — offering "Take Photo" (rear camera) / "Choose from
  /// Gallery".
  capturePrompt,

  /// A photo has been picked/captured and is shown full-size for the
  /// customer to confirm, retake, or choose a different one. Nothing
  /// uploaded yet.
  photoPreview,

  /// Re-encoding + uploading the photo to Storage. Cancellable.
  uploading,

  /// The `generateTryOn` callable is in flight. Not cancellable (already
  /// billable server-side); back navigation is intercepted with a
  /// confirmation instead of silently abandoning.
  generating,

  /// A result is available — either freshly generated, or a cached replay of
  /// an unexpired prior success for this exact attempt.
  success,

  /// The most recent attempt failed. [VirtualTryOnSessionViewModel.lastError]
  /// carries the mapped, customer-safe reason.
  failed,
}
