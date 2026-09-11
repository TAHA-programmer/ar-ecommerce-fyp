// ignore_for_file: prefer_initializing_formals
import 'package:flutter/foundation.dart';

import '../../../app/viewmodels/auth_session_state.dart';
import '../../../app/viewmodels/customer_shopping_state.dart';
import '../../../core/models/product/product_color_option.dart';
import '../../../core/models/product/product_size.dart';
import '../../product_details/models/product_detail_model.dart';
import '../../product_details/repositories/product_details_repository.dart';
import '../models/virtual_try_on_session_phase.dart';
import '../services/person_photo_processor.dart';
import '../services/virtual_try_on_exception.dart';
import '../services/virtual_try_on_idempotency.dart';
import '../services/virtual_try_on_photo_picker_service.dart';
import '../services/virtual_try_on_service.dart';

/// Drives the Virtual Try-On capture/upload/generate/result screen (Phase
/// 9.3 Stage 5) — see [VirtualTryOnSessionPhase] for the state machine.
///
/// Owns the idempotency-key lifecycle: the SAME key is reused for a retry of
/// the same attempt (rate-limited / transient / timeout, same photo, same
/// colour), and a FRESH key is minted whenever the attempt genuinely changes
/// — a different photo, a different colour (a different colour means a
/// different garment asset and therefore a materially different generation,
/// never safe to alias onto a prior attempt's cached result), or after a
/// photo-specific rejection.
class VirtualTryOnSessionViewModel extends ChangeNotifier {
  final ProductDetailsRepository _repository;
  final VirtualTryOnService _service;
  final VirtualTryOnPhotoPickerService _photoPicker;
  final CustomerShoppingState _shoppingState;
  final AuthSessionState _authSessionState;
  final String productId;

  VirtualTryOnSessionViewModel({
    required ProductDetailsRepository repository,
    required VirtualTryOnService service,
    required VirtualTryOnPhotoPickerService photoPicker,
    required CustomerShoppingState shoppingState,
    required AuthSessionState authSessionState,
    required this.productId,
    required String colorKey,
    String? size,
    required String idempotencyKey,
  }) : _repository = repository,
       _service = service,
       _photoPicker = photoPicker,
       _shoppingState = shoppingState,
       _authSessionState = authSessionState,
       currentColorKey = colorKey,
       currentSize = size,
       _idempotencyKey = idempotencyKey {
    _loadProduct();
  }

  bool isLoadingProduct = true;
  ProductDetailModel? product;
  String? loadError;

  String currentColorKey;
  String? currentSize;
  String _idempotencyKey;

  VirtualTryOnSessionPhase phase = VirtualTryOnSessionPhase.capturePrompt;

  /// `true` while a pick/upload/generate/delete call is in flight — guards
  /// every action method against a duplicate tap.
  bool isBusy = false;

  Uint8List? _photoJpegBytes;

  /// The exact bytes that will be (or were) uploaded — what the
  /// `photoPreview` screen shows.
  Uint8List? get previewBytes => _photoJpegBytes;

  /// A validation rejection for the most recent pick attempt, shown on the
  /// capture screen. Cleared on the next pick attempt.
  String? photoRejectionMessage;

  Uint8List? resultBytes;
  String? resultPath;
  DateTime? resultExpiresAt;

  VirtualTryOnException? lastError;

  /// `true` right after [changeSize] while a `success` result is showing —
  /// tells the view to show the honest "size doesn't change this preview"
  /// banner instead of implying a new image was generated.
  bool sizeOnlyChangedNotice = false;

  Future<void> _loadProduct() async {
    isLoadingProduct = true;
    notifyListeners();
    try {
      final loaded = await _repository.getProductDetails(productId);
      product = loaded;
      if (!loaded.hasRenderableVtoAsset) {
        loadError = "Virtual Try-On isn't available for this product.";
      }
    } catch (_) {
      loadError = 'Failed to load product details.';
    } finally {
      isLoadingProduct = false;
      notifyListeners();
    }
  }

  /// Colours eligible for a try-on preview (a resolvable garment asset) —
  /// the only colours offered by the in-session "change colour" chips.
  List<ProductColorOption> get eligibleColors {
    final p = product;
    if (p == null) return const [];
    return p.availableColors
        .where((c) => p.vtoGarmentForColor(c) != null)
        .toList();
  }

  List<ProductSize> get availableSizes => product?.availableSizes ?? const [];

  // ── Photo acquisition ────────────────────────────────────────────────────

  Future<void> captureFromCamera() =>
      _pickPhoto(_photoPicker.captureFromCamera);

  Future<void> pickFromGallery() => _pickPhoto(_photoPicker.pickFromGallery);

  Future<void> _pickPhoto(Future<Uint8List?> Function() picker) async {
    if (isBusy) return;
    isBusy = true;
    photoRejectionMessage = null;
    notifyListeners();
    try {
      final raw = await picker();
      if (raw == null) return; // cancelled — stay put, not an error
      final processed = PersonPhotoProcessor.processToJpeg(raw);
      _photoJpegBytes = processed;
      phase = VirtualTryOnSessionPhase.photoPreview;
    } on PersonPhotoValidationException catch (e) {
      photoRejectionMessage = e.message;
    } catch (_) {
      photoRejectionMessage =
          "That photo couldn't be used. Please try another.";
    } finally {
      isBusy = false;
      notifyListeners();
    }
  }

  /// "Retake" / "Choose Different Photo" from the preview screen — discards
  /// the picked photo, no Storage call needed (nothing was ever uploaded).
  void discardPickedPhoto() {
    _generationEpoch++;
    _photoJpegBytes = null;
    phase = VirtualTryOnSessionPhase.capturePrompt;
    notifyListeners();
  }

  // ── Generation ───────────────────────────────────────────────────────────

  /// "Use This Photo" from the preview screen.
  Future<void> usePhotoAndGenerate() async {
    if (_photoJpegBytes == null || isBusy) return;
    await _runGeneration();
  }

  /// In-session "change colour" (shown once a result is displayed). Reuses
  /// the photo already in memory — no need to retake — but ALWAYS mints a
  /// fresh idempotency key: a different colour resolves to a different
  /// garment asset, so aliasing it onto the previous attempt's key would risk
  /// the server returning the OLD colour's cached result instead of running a
  /// new generation (the server keys its cache purely by
  /// `(uid, idempotencyKey)`, not by colour).
  Future<void> changeColor(String newColorKey) async {
    if (newColorKey == currentColorKey || isBusy) return;
    currentColorKey = newColorKey;
    _idempotencyKey = generateVirtualTryOnIdempotencyKey();
    sizeOnlyChangedNotice = false;
    notifyListeners();
    if (_photoJpegBytes != null) {
      await _runGeneration();
    }
  }

  /// In-session "change size". Size never affects which garment asset is
  /// used (D6) — this never triggers a new generation call, only updates
  /// what "Add to Cart" will use, and (while a result is showing) surfaces an
  /// honest "this won't change the preview" notice.
  void changeSize(String? newSize) {
    if (newSize == currentSize) return;
    currentSize = newSize;
    if (phase == VirtualTryOnSessionPhase.success) {
      sizeOnlyChangedNotice = true;
    }
    notifyListeners();
  }

  /// Retry after a [failed] state. A same-photo-safe failure (rate limit /
  /// transient / timeout / eligibility) mints a new key and retries with the
  /// photo already in memory; a photo-specific rejection (`PHOTO_INVALID`,
  /// `PROVIDER_REFUSED`) instead returns to the capture screen so the
  /// customer picks a different photo.
  Future<void> retryAfterFailure() async {
    if (isBusy) return;
    final err = lastError;
    _idempotencyKey = generateVirtualTryOnIdempotencyKey();
    if (err != null &&
        err.isRetryableWithSamePhoto &&
        _photoJpegBytes != null) {
      await _runGeneration();
    } else {
      _photoJpegBytes = null;
      lastError = null;
      phase = VirtualTryOnSessionPhase.capturePrompt;
      notifyListeners();
    }
  }

  /// "Retake Photo" from a `success` result — always a fresh attempt. The
  /// result being abandoned is best-effort deleted (fire-and-forget, mirrors
  /// `_recentlyViewed?.recordView` elsewhere in the app) rather than left for
  /// the 24h TTL sweep alone — its `resultPath` is about to be discarded and
  /// would otherwise be unrecoverable.
  void startRetake() {
    if (isBusy) return;
    _generationEpoch++;
    final stalePath = resultPath;
    if (stalePath != null) {
      _service.deleteResultBestEffort(stalePath);
    }
    _idempotencyKey = generateVirtualTryOnIdempotencyKey();
    _photoJpegBytes = null;
    resultBytes = null;
    resultPath = null;
    resultExpiresAt = null;
    lastError = null;
    sizeOnlyChangedNotice = false;
    phase = VirtualTryOnSessionPhase.capturePrompt;
    notifyListeners();
  }

  /// Bumped by [_runGeneration] and by every method that resets state out
  /// from under an in-flight generation ([cancelDuringUpload],
  /// [discardPickedPhoto], [deletePreviewAndReset], [startRetake]). Each
  /// running [_runGeneration] captures its own value at start and checks it
  /// after every `await` — a stale continuation (e.g. the upload call
  /// finally resolving well after the customer already cancelled and moved
  /// on) silently stops touching state instead of clobbering whatever the
  /// customer did next.
  int _generationEpoch = 0;

  Future<void> _runGeneration() async {
    final uid = _authSessionState.userId;
    final bytes = _photoJpegBytes;
    if (uid == null) {
      lastError = const VirtualTryOnException.notSignedIn();
      phase = VirtualTryOnSessionPhase.failed;
      notifyListeners();
      return;
    }
    if (bytes == null) return;

    // A prior successful result may still be referenced here (e.g.
    // `changeColor` just moved to a new colour/idempotency key with the old
    // colour's result still showing, or an earlier success's result was
    // never cleared before a later attempt on this same session failed and
    // was retried). Its `resultPath` is about to be overwritten or the
    // attempt is about to fail without ever revisiting it — either way it
    // is being abandoned, so delete it best-effort now (fire-and-forget,
    // doesn't block this attempt) rather than rely solely on the 24h TTL
    // sweep, which the design treats as a safety fallback, not the primary
    // deletion path (D4).
    final stalePath = resultPath;
    if (stalePath != null) {
      resultPath = null;
      resultBytes = null;
      resultExpiresAt = null;
      _service.deleteResultBestEffort(stalePath);
    }

    final epoch = ++_generationEpoch;
    bool isCurrent() => epoch == _generationEpoch;

    isBusy = true;
    lastError = null;
    sizeOnlyChangedNotice = false;
    phase = VirtualTryOnSessionPhase.uploading;
    notifyListeners();

    try {
      await _service.uploadPersonPhoto(
        uid: uid,
        idempotencyKey: _idempotencyKey,
        personPhotoJpegBytes: bytes,
      );
      if (!isCurrent()) return;

      phase = VirtualTryOnSessionPhase.generating;
      notifyListeners();

      final result = await _service.generate(
        uid: uid,
        productId: productId,
        colorKey: currentColorKey,
        size: currentSize,
        idempotencyKey: _idempotencyKey,
        consent: true,
      );
      if (!isCurrent()) return;

      final downloaded = await _service.downloadResult(
        result.resultPath,
        maxSize: 15 * 1024 * 1024,
      );
      if (!isCurrent()) return;

      resultBytes = downloaded;
      resultPath = result.resultPath;
      resultExpiresAt = result.expiresAt;
      phase = VirtualTryOnSessionPhase.success;
    } on VirtualTryOnException catch (e) {
      if (!isCurrent()) return;
      lastError = e;
      phase = VirtualTryOnSessionPhase.failed;
    } catch (_) {
      if (!isCurrent()) return;
      lastError = const VirtualTryOnException.network();
      phase = VirtualTryOnSessionPhase.failed;
    } finally {
      if (isCurrent()) {
        isBusy = false;
        notifyListeners();
      }
    }
  }

  // ── Cancellation / cleanup ───────────────────────────────────────────────

  /// Cancel while [VirtualTryOnSessionPhase.uploading] — best-effort deletes
  /// whatever was uploaded and returns to the photo-preview screen (the photo
  /// itself is still valid and in memory).
  Future<void> cancelDuringUpload() async {
    // Invalidate the in-flight `_runGeneration` FIRST — its `uploadPersonPhoto`
    // await may still be pending and must never resume mutating `phase`
    // after this cancel has already moved the screen back to
    // `photoPreview`.
    _generationEpoch++;
    final uid = _authSessionState.userId;
    if (uid != null) {
      await _service.deleteUploadBestEffort(
        uid: uid,
        idempotencyKey: _idempotencyKey,
      );
    }
    isBusy = false;
    phase = VirtualTryOnSessionPhase.photoPreview;
    notifyListeners();
  }

  /// "Delete This Preview" — explicit customer request. Deletes the result,
  /// then resets to a fresh capture attempt.
  Future<void> deletePreviewAndReset() async {
    _generationEpoch++;
    final path = resultPath;
    if (path != null) {
      await _service.deleteResultBestEffort(path);
    }
    resultBytes = null;
    resultPath = null;
    resultExpiresAt = null;
    _photoJpegBytes = null;
    sizeOnlyChangedNotice = false;
    _idempotencyKey = generateVirtualTryOnIdempotencyKey();
    phase = VirtualTryOnSessionPhase.capturePrompt;
    notifyListeners();
  }

  /// D4 — "leaves the completed result flow" deletes the result. Call this
  /// before popping the screen from a `success` state (the "Done" action, or
  /// back navigation).
  Future<void> deleteResultOnLeave() async {
    final path = resultPath;
    if (path == null) return;
    await _service.deleteResultBestEffort(path);
  }

  // ── Add to Cart ──────────────────────────────────────────────────────────

  /// Adds the exact currently-selected variant to the cart via the existing
  /// shared cart path — no new cart/order code.
  Future<String?> addSelectedVariantToCart() {
    final p = product;
    final color = _colorOptionFor(currentColorKey);
    if (p == null || color == null) {
      return Future.value('Something went wrong adding this to your cart.');
    }
    final priceDigits = p.summary.currentPrice.replaceAll(
      RegExp(r'[^0-9]'),
      '',
    );
    return _shoppingState.addToCart(
      productId,
      quantity: 1,
      selectedColor: color,
      selectedSize: _sizeOptionFor(currentSize),
      priceAmountSnapshot: int.tryParse(priceDigits) ?? 0,
    );
  }

  ProductColorOption? _colorOptionFor(String name) {
    for (final c in ProductColorOption.values) {
      if (c.name == name) return c;
    }
    return null;
  }

  ProductSize? _sizeOptionFor(String? name) {
    if (name == null) return null;
    for (final s in ProductSize.values) {
      if (s.name == name) return s;
    }
    return null;
  }
}
