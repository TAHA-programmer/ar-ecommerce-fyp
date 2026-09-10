import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/product/product_ar_metadata.dart';
import '../../../../core/models/product/product_experience_type.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/models/product/product_publication_status.dart';
import '../../../../core/models/product/product_vto_metadata.dart';
import '../../../../core/models/product/product_vto_model_type.dart';
import '../../../../core/services/firebase_storage_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../room_ar/model_delivery/glb_inspector.dart';
import '../models/admin_ar_model_candidate.dart';
import '../models/admin_vto_garment_candidate.dart';
import '../services/ar_model_file_picker.dart';
import '../services/vto_garment_file_picker.dart';
import '../utils/admin_glb_validator.dart';
import '../utils/admin_vto_garment_validator.dart';

enum ArMediaManagementMode { general, productScoped }

/// The Virtual Try-On garment-asset workflow state for the selected product,
/// derived from the working product plus any staged change (Phase 9.3 Stage 3).
/// Exact mirror of [AdminRoomArModelStatus].
enum AdminVtoAssetStatus {
  /// The product opts into Virtual Try-On but has no garment config at all.
  noAsset,

  /// A committed, renderable config; the customer entry point is ON and the
  /// product is customer-visible.
  live,

  /// A committed, renderable config; the admin has switched the entry point
  /// OFF (assets retained, one toggle from live).
  disabled,

  /// A committed config that is present but not renderable — it needs a fix
  /// (re-upload / corrected metadata / missing per-colour asset). Never
  /// customer-visible.
  broken,

  /// A committed, renderable config with the entry point ON — **but this
  /// product is not customer-visible yet** (unpublished / inactive / a colour
  /// still uncovered). Shown honestly, never as "Live".
  readyNotApproved,

  /// One or more validated garment images (or a category change) are staged,
  /// awaiting Save.
  stagedUpload,

  /// A pending enable/disable of the entry point is staged, awaiting Save.
  stagedToggle,

  /// A pending permanent deletion of the whole VTO config is staged, awaiting
  /// Save.
  stagedDeletion,
}

/// The literal slot key for the single optional product-wide garment asset.
const String kVtoDefaultSlot = 'default';

/// Ordered garment categories for the admin dropdown — the same closed set as
/// [ProductVtoMetadata.supportedGarmentCategories], with a stable display order.
const List<String> kVtoGarmentCategoryOptions = [
  'top',
  'outerwear',
  'dress',
  'bottom',
];

/// The Room-AR model workflow state for the selected product, derived from the
/// working product plus any staged change (Phase 9.2 R16).
enum AdminRoomArModelStatus {
  /// The product opts into Room AR but has no model contract at all.
  noModel,

  /// A committed, renderable model; the customer entry point is ON.
  live,

  /// A committed, renderable model; the admin has switched the entry point OFF
  /// (model retained, one toggle from live).
  disabled,

  /// A committed model whose contract is present but not renderable — it needs
  /// a fix (re-upload / corrected metadata). Never customer-visible.
  broken,

  /// A committed, renderable model with the entry point ON — **but this
  /// product is not yet customer-visible** (unpublished and/or inactive;
  /// see `productIsCustomerApproved`, Phase 9.2 §17-follow-up — no longer
  /// tied to `RoomArProductManifest`/a static `storage.rules` allowlist,
  /// both now metadata-driven). The model + metadata are valid, yet
  /// customers still cannot launch it until the product itself is published
  /// and active. Shown honestly, never as "Live".
  readyNotApproved,

  /// A validated replacement/new GLB is staged, awaiting Save.
  stagedUpload,

  /// A pending enable/disable of the entry point is staged, awaiting Save.
  stagedToggle,

  /// A pending permanent deletion of the model is staged, awaiting Save.
  stagedDeletion,
}

class ArMediaRouteArguments {
  final ProductModel product;

  const ArMediaRouteArguments.productScoped(this.product);
}

class ArMediaManagementViewModel extends ChangeNotifier {
  final CommerceDatabase? _database;
  final ArMediaManagementMode mode;
  final StorageService _storage;
  final ArModelFilePicker _picker;
  final VtoGarmentFilePicker _vtoPicker;
  final GlbInspector _inspector;

  /// Product-scoped mode only: the product exactly as it was handed in — the
  /// "what changed" baseline when there is no database to read from.
  final ProductModel? _initialProduct;

  ArMediaManagementViewModel(
    CommerceDatabase database, {
    StorageService? storageService,
    ArModelFilePicker? filePicker,
    VtoGarmentFilePicker? vtoFilePicker,
    GlbInspector inspector = const GlbInspector(),
  }) : this.general(
         database,
         storageService: storageService,
         filePicker: filePicker,
         vtoFilePicker: vtoFilePicker,
         inspector: inspector,
       );

  ArMediaManagementViewModel.general(
    CommerceDatabase database, {
    StorageService? storageService,
    ArModelFilePicker? filePicker,
    VtoGarmentFilePicker? vtoFilePicker,
    this._inspector = const GlbInspector(),
  }) : _database = database,
       _storage = storageService ?? FirebaseStorageService(),
       _picker = filePicker ?? const FilePickerArModelFilePicker(),
       _vtoPicker = vtoFilePicker ?? const FilePickerVtoGarmentFilePicker(),
       _initialProduct = null,
       mode = ArMediaManagementMode.general {
    database.addListener(_onDatabaseChanged);
    _selectFirstEligibleProduct();
  }

  ArMediaManagementViewModel.productScoped(
    ProductModel product, {
    StorageService? storageService,
    ArModelFilePicker? filePicker,
    VtoGarmentFilePicker? vtoFilePicker,
    this._inspector = const GlbInspector(),
  }) : _database = null,
       _storage = storageService ?? FirebaseStorageService(),
       _picker = filePicker ?? const FilePickerArModelFilePicker(),
       _vtoPicker = vtoFilePicker ?? const FilePickerVtoGarmentFilePicker(),
       _initialProduct = product,
       mode = ArMediaManagementMode.productScoped {
    _loadProduct(product);
  }

  ProductModel? _workingProduct;
  String? _selectedProductId;
  bool _hasUnsavedChanges = false;

  String? get selectedProductId => _selectedProductId;
  ProductModel? get selectedProduct => _workingProduct;
  bool get isProductScoped => mode == ArMediaManagementMode.productScoped;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  // ── Room-AR production state (R16) ─────────────────────────────────────
  AdminArModelCandidate? _candidate;
  AdminArModelCandidate? get stagedCandidate => _candidate;

  bool _isValidatingModel = false;
  bool get isValidatingModel => _isValidatingModel;

  String? _modelValidationError;
  String? get modelValidationError => _modelValidationError;

  bool _isUploadingModel = false;
  bool get isUploadingModel => _isUploadingModel;

  double _modelUploadProgress = 0;
  double get modelUploadProgress => _modelUploadProgress;

  String? _modelWorkflowNote;
  String? get modelWorkflowNote => _modelWorkflowNote;

  /// Staged intent to permanently delete the committed model on Save.
  bool _stagedModelDeletion = false;

  /// The committed contract on the working product (may be non-renderable).
  ProductArMetadata? get committedArMetadata => _workingProduct?.arMetadata;

  /// Honest per-field reasons a committed contract is not renderable, for the
  /// admin "needs a fix" state. Empty when the model is renderable or absent.
  List<String> get committedModelIssues {
    final ar = _workingProduct?.arMetadata;
    if (ar == null || ar.isRenderable) return const [];
    return ProductArMetadata.validationIssues(ar.toFirestoreFields());
  }

  /// The staged value of the customer Room-AR entry point.
  bool get roomArEntryPointEnabled =>
      _workingProduct != null && !_workingProduct!.arModelDisabled;

  List<ProductModel> get eligibleProducts {
    final database = _database;
    if (database == null) {
      return _workingProduct == null ? const [] : [_workingProduct!];
    }
    return database.products
        .where(
          (product) =>
              product.experienceType == ProductExperienceType.roomAr ||
              product.experienceType == ProductExperienceType.virtualTryOn,
        )
        .toList();
  }

  bool get isRoomAr =>
      selectedProduct?.experienceType == ProductExperienceType.roomAr;

  bool get isVirtualTryOn =>
      selectedProduct?.experienceType == ProductExperienceType.virtualTryOn;

  /// "There is something to configure/save" for the Room-AR side — a committed
  /// model, a staged candidate, or a staged toggle/deletion.
  bool get isRoomArConfigured =>
      _candidate != null ||
      _stagedModelDeletion ||
      committedArMetadata != null ||
      _workingProduct?.arModelDisabled == true;

  /// "There is something to configure/save" for the Virtual Try-On side — a
  /// committed config, staged garment candidates, a category change, or a
  /// staged toggle/deletion.
  bool get isVtoConfigured =>
      _vtoCandidates.isNotEmpty ||
      _stagedVtoDeletion ||
      committedVtoMetadata != null ||
      _workingProduct?.vtoDisabled == true ||
      _vtoCategoryChanged;

  /// `true` when the selected product actually meets every condition
  /// `storage.rules`' now-dynamic, metadata-driven `isApprovedArProduct()`
  /// checks against its own live document (Phase 9.2 §17-follow-up):
  /// published, active, a renderable `ar*` contract, and enabled. **No
  /// longer tied to `RoomArProductManifest`** — that was a static,
  /// manually-maintained list; a brand-new Admin-created product is now
  /// "Live" the moment its own document qualifies, with no manifest entry
  /// at all. A valid model on a product that is unpublished/inactive is
  /// real, but no customer can launch it yet regardless of the model.
  bool get productIsCustomerApproved {
    final product = _workingProduct;
    return product != null &&
        product.hasRenderableArModel &&
        product.isActive &&
        product.publicationStatus == ProductPublicationStatus.published;
  }

  AdminRoomArModelStatus get roomArModelStatus {
    if (_candidate != null) return AdminRoomArModelStatus.stagedUpload;
    if (_stagedModelDeletion) return AdminRoomArModelStatus.stagedDeletion;
    final product = _workingProduct;
    final ar = product?.arMetadata;
    if (product == null || ar == null) {
      // A staged enable/disable with no model is impossible (guarded), so this
      // is just "no model".
      return AdminRoomArModelStatus.noModel;
    }
    if (!ar.isRenderable) return AdminRoomArModelStatus.broken;
    final committedDisabled = _baselineProduct?.arModelDisabled ?? false;
    if (product.arModelDisabled != committedDisabled) {
      return AdminRoomArModelStatus.stagedToggle;
    }
    if (product.arModelDisabled) return AdminRoomArModelStatus.disabled;
    // A valid, enabled model — but honest about whether a customer can
    // actually launch it.
    return productIsCustomerApproved
        ? AdminRoomArModelStatus.live
        : AdminRoomArModelStatus.readyNotApproved;
  }

  /// `true` when a delete would strand a live customer experience — the UI
  /// forces "disable first" before offering the destructive path. A product
  /// that is not customer-approved has no live experience to strand, so the
  /// "disable first" gate does not apply there.
  bool get canStageModelDeletion =>
      committedArMetadata != null &&
      !_stagedModelDeletion &&
      (!productIsCustomerApproved ||
          (_workingProduct?.arModelDisabled ?? false));

  // ── Virtual Try-On production state (Phase 9.3 Stage 3) ────────────────
  //
  // Exact mirror of the Room-AR side above, adapted for a 2-D image with one
  // asset per product colour (+ an optional product-wide `default`).

  /// Slot key (`'default'` or a `ProductColorOption.name`) -> a validated,
  /// staged-but-not-uploaded garment image.
  final Map<String, AdminVtoGarmentCandidate> _vtoCandidates = {};

  /// The staged garment category (`null` = unchanged from the committed config
  /// / not yet set). Read through [vtoGarmentCategory].
  String? _vtoGarmentCategory;

  /// Staged intent to permanently delete the whole VTO config on Save.
  bool _stagedVtoDeletion = false;

  bool _isValidatingGarment = false;
  String? _validatingGarmentSlot;
  String? _garmentValidationError;
  bool _isUploadingGarment = false;
  double _garmentUploadProgress = 0;
  String? _vtoWorkflowNote;

  Map<String, AdminVtoGarmentCandidate> get stagedVtoCandidates =>
      Map.unmodifiable(_vtoCandidates);
  bool get isValidatingGarment => _isValidatingGarment;
  String? get validatingGarmentSlot => _validatingGarmentSlot;
  String? get garmentValidationError => _garmentValidationError;
  bool get isUploadingGarment => _isUploadingGarment;
  double get garmentUploadProgress => _garmentUploadProgress;

  /// Set when a save / delete's Firestore write **succeeded** but the
  /// best-effort Storage cleanup of a superseded / removed garment object
  /// failed. Honest UI note; the (correct) Firestore write is never undone.
  String? get vtoWorkflowNote => _vtoWorkflowNote;

  /// The committed VTO contract on the working product (may be non-renderable).
  ProductVtoMetadata? get committedVtoMetadata => _workingProduct?.vtoMetadata;

  /// The effective garment category to show — staged value, else the committed
  /// value, else the first supported category.
  String get vtoGarmentCategory =>
      _vtoGarmentCategory ??
      committedVtoMetadata?.garmentCategory ??
      kVtoGarmentCategoryOptions.first;

  /// `true` only when the admin has picked a category that differs from the
  /// committed one. A category-only edit is savable when a committed config
  /// already exists; it is meaningless with no config (nothing to write).
  bool get _vtoCategoryChanged {
    final committed = committedVtoMetadata?.garmentCategory;
    if (_vtoGarmentCategory == null || committed == null) return false;
    return _vtoGarmentCategory != committed;
  }

  /// Honest per-field reasons the committed VTO config is not renderable — for
  /// the admin "needs a fix" state. Empty when renderable or absent.
  List<String> get committedVtoIssues {
    final vto = _workingProduct?.vtoMetadata;
    if (vto == null || vto.isRenderable) return const [];
    return vto.issues;
  }

  /// The garment slots to configure for the selected product: one per available
  /// colour (its `ProductColorOption.name`), then the optional `default` slot.
  List<String> get vtoSlots {
    final product = _workingProduct;
    if (product == null) return const [];
    return [...product.availableColors.map((c) => c.name), kVtoDefaultSlot];
  }

  AdminVtoGarmentCandidate? vtoCandidateForSlot(String slot) =>
      _vtoCandidates[slot];

  /// The committed asset for [slot] (if any) — a `ProductColorOption.name` or
  /// `default`.
  VtoGarmentAsset? committedVtoAssetForSlot(String slot) {
    final vto = committedVtoMetadata;
    if (vto == null) return null;
    return slot == kVtoDefaultSlot
        ? vto.garmentDefault
        : vto.garmentsByColor[slot];
  }

  /// `true` when a committed asset exists for [slot] but its stored Storage
  /// path is **not** exactly this product's own expected path for the slot
  /// (cross-product / hand-edited / wrong-version). Such an asset is never
  /// previewed, never trusted, and must be replaced. Distinct from
  /// [canPreviewCommittedGarment] (which is also `false` mid-deletion).
  bool committedGarmentPathIsForeign(String slot) {
    final asset = committedVtoAssetForSlot(slot);
    final product = _workingProduct;
    if (asset == null || product == null) return false;
    return !asset.matchesExpectedPath(product.id, slot);
  }

  /// The staged value of the customer Virtual Try-On entry point.
  bool get vtoEntryPointEnabled =>
      _workingProduct != null && !_workingProduct!.vtoDisabled;

  /// `true` when the product actually meets every condition for a customer
  /// launch: a renderable, owned config, every colour covered, entry point on,
  /// and the product itself published + active. Mirrors
  /// [productIsCustomerApproved].
  bool get vtoProductIsCustomerApproved {
    final product = _workingProduct;
    return product != null &&
        product.hasRenderableVtoAsset &&
        product.isActive &&
        product.publicationStatus == ProductPublicationStatus.published;
  }

  AdminVtoAssetStatus get vtoAssetStatus {
    if (_stagedVtoDeletion) return AdminVtoAssetStatus.stagedDeletion;
    if (_vtoCandidates.isNotEmpty || _vtoCategoryChanged) {
      return AdminVtoAssetStatus.stagedUpload;
    }
    final product = _workingProduct;
    final vto = product?.vtoMetadata;
    if (product == null || vto == null) return AdminVtoAssetStatus.noAsset;
    if (!vto.isRenderableForProduct(product.id)) {
      return AdminVtoAssetStatus.broken;
    }
    final committedDisabled = _baselineProduct?.vtoDisabled ?? false;
    if (product.vtoDisabled != committedDisabled) {
      return AdminVtoAssetStatus.stagedToggle;
    }
    if (product.vtoDisabled) return AdminVtoAssetStatus.disabled;
    return vtoProductIsCustomerApproved
        ? AdminVtoAssetStatus.live
        : AdminVtoAssetStatus.readyNotApproved;
  }

  /// `true` when a delete would strand a live customer experience — the UI
  /// forces "disable first". A product not customer-approved has nothing to
  /// strand, so the gate does not apply there.
  bool get canStageVtoDeletion =>
      committedVtoMetadata != null &&
      !_stagedVtoDeletion &&
      (!vtoProductIsCustomerApproved ||
          (_workingProduct?.vtoDisabled ?? false));

  /// `true` when the admin can inline-preview a committed asset for [slot]
  /// (downloaded through Storage) — a staged candidate previews from its local
  /// file always. Requires the stored path to be **exactly this product's own**
  /// expected path for the slot ([VtoGarmentAsset.matchesExpectedPath]): a
  /// well-formed but cross-product / hand-edited path is never downloaded.
  bool canPreviewCommittedGarment(String slot) {
    final asset = committedVtoAssetForSlot(slot);
    final product = _workingProduct;
    return asset != null &&
        product != null &&
        asset.isRenderable &&
        asset.matchesExpectedPath(product.id, slot) &&
        !_stagedVtoDeletion;
  }

  /// The product as it was before any staged change — the database's copy in
  /// general mode, the handed-in product in product-scoped mode.
  ProductModel? get _baselineProduct => _committedProduct ?? _initialProduct;

  /// The committed product as the database currently holds it — the baseline
  /// for "what changed" in general mode. `null` in product-scoped mode.
  ProductModel? get _committedProduct {
    final database = _database;
    final id = _selectedProductId;
    if (database == null || id == null) return null;
    try {
      return database.getProductById(id);
    } catch (_) {
      return null;
    }
  }

  // ── selection ─────────────────────────────────────────────────────────
  void _selectFirstEligibleProduct() {
    final products = eligibleProducts;
    if (products.isEmpty) {
      _workingProduct = null;
      _selectedProductId = null;
      _hasUnsavedChanges = false;
      _resetRoomArStaging();
      _resetVtoStaging();
      return;
    }
    _loadProduct(products.first);
  }

  void _onDatabaseChanged() {
    if (_hasUnsavedChanges) return;
    final database = _database;
    if (database == null) return;
    final matching = database.products
        .where((product) => product.id == _selectedProductId)
        .toList();
    if (matching.isNotEmpty &&
        matching.first.experienceType != ProductExperienceType.none) {
      _loadProduct(matching.first);
    } else {
      _selectFirstEligibleProduct();
    }
    notifyListeners();
  }

  void selectProduct(String productId) {
    if (isProductScoped || _selectedProductId == productId) return;
    final matches = eligibleProducts
        .where((product) => product.id == productId)
        .toList();
    if (matches.isEmpty) return;
    _loadProduct(matches.first);
    notifyListeners();
  }

  void _loadProduct(ProductModel product) {
    _workingProduct = product;
    _selectedProductId = product.id;
    _hasUnsavedChanges = false;
    _resetRoomArStaging();
    _resetVtoStaging();
  }

  void _resetRoomArStaging() {
    _candidate = null;
    _stagedModelDeletion = false;
    _isValidatingModel = false;
    _modelValidationError = null;
    _isUploadingModel = false;
    _modelUploadProgress = 0;
    _modelWorkflowNote = null;
  }

  void _resetVtoStaging() {
    _vtoCandidates.clear();
    _vtoGarmentCategory = null;
    _stagedVtoDeletion = false;
    _isValidatingGarment = false;
    _validatingGarmentSlot = null;
    _garmentValidationError = null;
    _isUploadingGarment = false;
    _garmentUploadProgress = 0;
    _vtoWorkflowNote = null;
  }

  void _stage(ProductModel product) {
    _workingProduct = product;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  // ── Room-AR: pick + validate a GLB ────────────────────────────────────

  /// Opens the platform picker, validates the picked `.glb` from its bytes
  /// (structure + measured bounding box + SHA-256), and stages it as a
  /// [AdminArModelCandidate] with its measured dimensions pre-filled. Any
  /// failure lands in [modelValidationError] and nothing is staged.
  Future<void> pickAndValidateModel() async {
    if (!isRoomAr || _isValidatingModel) return;
    final File? file;
    try {
      file = await _picker.pickGlb();
    } on ArModelFilePickException catch (e) {
      _modelValidationError = e.message;
      notifyListeners();
      return;
    }
    if (file == null) return; // cancelled
    await validateModelFile(file);
  }

  /// Validate a specific file (seam the picker calls; also directly callable
  /// from tests).
  Future<void> validateModelFile(File file) async {
    if (!isRoomAr) return;
    _isValidatingModel = true;
    _modelValidationError = null;
    notifyListeners();
    try {
      final inspection = await inspectArGlbFile(file, inspector: _inspector);
      final previous = _committedProduct?.arMetadata ?? committedArMetadata;
      final nextVersion = _nextVersion(previous);
      _candidate = AdminArModelCandidate(
        file: file,
        sizeBytes: inspection.sizeBytes,
        sha256: inspection.sha256,
        measuredM: inspection.measuredM,
        floorCentred: inspection.floorCentred,
        widthM: _round(inspection.measuredM.width),
        depthM: _round(inspection.measuredM.depth),
        heightM: _round(inspection.measuredM.height),
        scale: 1.0,
        targetVersion: nextVersion,
      );
      _stagedModelDeletion = false;
      _modelWorkflowNote = null;
      _hasUnsavedChanges = true;
    } on GlbValidationException catch (e) {
      _candidate = null;
      _modelValidationError = e.message;
    } catch (_) {
      _candidate = null;
      _modelValidationError = 'This 3D model could not be validated.';
    } finally {
      _isValidatingModel = false;
      notifyListeners();
    }
  }

  /// Re-check the staged GLB against admin-entered dimensions. Returns `false`
  /// (and sets [modelValidationError]) when the model's real size no longer
  /// matches, so the admin cannot save a mismatched contract.
  Future<bool> updateStagedDimensions({
    double? widthM,
    double? depthM,
    double? heightM,
  }) async {
    final candidate = _candidate;
    if (candidate == null) return false;
    final next = candidate.copyWith(
      widthM: widthM,
      depthM: depthM,
      heightM: heightM,
    );
    try {
      await inspectArGlbFile(
        candidate.file,
        inspector: _inspector,
        expected: GlbExpectedBox(
          widthM: next.widthM,
          depthM: next.depthM,
          heightM: next.heightM,
        ),
      );
    } on GlbValidationException catch (e) {
      _modelValidationError = e.message;
      notifyListeners();
      return false;
    }
    _candidate = next;
    _modelValidationError = null;
    _hasUnsavedChanges = true;
    notifyListeners();
    return true;
  }

  bool updateStagedScale(String value) {
    final candidate = _candidate;
    final scale = double.tryParse(value.trim());
    if (candidate == null || scale == null || scale <= 0 || scale > 10) {
      return false;
    }
    _candidate = candidate.copyWith(scale: scale);
    _hasUnsavedChanges = true;
    notifyListeners();
    return true;
  }

  void discardStagedModel() {
    if (_candidate == null) return;
    _candidate = null;
    _modelValidationError = null;
    _modelWorkflowNote = null;
    _recomputeDirty();
    notifyListeners();
  }

  /// Stage switching the customer entry point on/off. Only meaningful when a
  /// committed renderable model exists.
  void setRoomArEntryPointEnabled(bool enabled) {
    final product = _workingProduct;
    if (product == null || product.arMetadata == null) return;
    if (product.arModelDisabled == !enabled) return;
    _stage(product.copyWith(arModelDisabled: !enabled));
  }

  /// Stage a permanent deletion of the committed model. Guarded: the entry
  /// point must already be disabled (see [canStageModelDeletion]).
  void stageModelDeletion() {
    if (!canStageModelDeletion) return;
    _stagedModelDeletion = true;
    _candidate = null;
    _modelWorkflowNote = null;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void cancelStagedModelDeletion() {
    if (!_stagedModelDeletion) return;
    _stagedModelDeletion = false;
    _recomputeDirty();
    notifyListeners();
  }

  void _recomputeDirty() {
    final baseline = _baselineProduct;
    _hasUnsavedChanges =
        _candidate != null ||
        _stagedModelDeletion ||
        _vtoCandidates.isNotEmpty ||
        _stagedVtoDeletion ||
        _vtoCategoryChanged ||
        (baseline != null &&
            _workingProduct != null &&
            (baseline.arModelDisabled != _workingProduct!.arModelDisabled ||
                baseline.vtoDisabled != _workingProduct!.vtoDisabled ||
                baseline.vtoModelType != _workingProduct!.vtoModelType));
  }

  int _nextVersion(ProductArMetadata? previous) {
    if (previous == null) return 1;
    final parsed = int.tryParse(previous.modelVersion.trim());
    return (parsed == null || parsed < 1 ? 1 : parsed) + 1;
  }

  static double _round(double m) => (m * 1000).roundToDouble() / 1000;

  // ── preview ───────────────────────────────────────────────────────────

  /// The admin can 3D-preview a staged candidate (from its local file) always,
  /// or a committed renderable model (downloaded through Storage — client read
  /// currently only succeeds for the four allowlisted products; see the R16
  /// notes / `storage.rules`).
  bool get canPreviewModel =>
      _candidate != null ||
      (committedArMetadata?.isRenderable ?? false) && !_stagedModelDeletion;

  /// Args for the admin preview route: a local file path (staged candidate)
  /// takes precedence; otherwise the committed contract.
  ({
    String? localFilePath,
    ProductArMetadata? metadata,
    String title,
    double w,
    double d,
    double h,
  })?
  get previewSpec {
    final product = _workingProduct;
    if (product == null) return null;
    final candidate = _candidate;
    if (candidate != null) {
      return (
        localFilePath: candidate.file.path,
        metadata: null,
        title: product.title,
        w: candidate.widthM,
        d: candidate.depthM,
        h: candidate.heightM,
      );
    }
    final ar = committedArMetadata;
    if (ar != null && ar.isRenderable && !_stagedModelDeletion) {
      return (
        localFilePath: null,
        metadata: ar,
        title: product.title,
        w: ar.widthM,
        d: ar.depthM,
        h: ar.heightM,
      );
    }
    return null;
  }

  // ── Virtual Try-On: production garment pipeline (Phase 9.3 Stage 3) ────

  void setVtoModelType(ProductVtoModelType value) {
    final product = selectedProduct;
    if (product == null || !isVirtualTryOn || product.vtoModelType == value) {
      return;
    }
    _stage(product.copyWith(vtoModelType: value));
  }

  /// Stage a garment category. Rejected (silently) when it is not one of
  /// [ProductVtoMetadata.supportedGarmentCategories].
  void setVtoGarmentCategory(String value) {
    if (!isVirtualTryOn) return;
    if (!ProductVtoMetadata.supportedGarmentCategories.contains(value)) return;
    if (vtoGarmentCategory == value) return;
    _vtoGarmentCategory = value;
    _recomputeDirty();
    notifyListeners();
  }

  /// Opens the platform picker for [slot] (`'default'` or a
  /// `ProductColorOption.name`), validates the picked JPEG/PNG from its bytes
  /// (signature + dimensions + SHA-256), and stages it as an
  /// [AdminVtoGarmentCandidate]. Any failure lands in [garmentValidationError]
  /// and nothing is staged.
  Future<void> pickAndValidateGarment(String slot) async {
    if (!isVirtualTryOn || _isValidatingGarment) return;
    if (!vtoSlots.contains(slot)) return;
    final File? file;
    try {
      file = await _vtoPicker.pickImage();
    } on VtoGarmentFilePickException catch (e) {
      _garmentValidationError = e.message;
      notifyListeners();
      return;
    }
    if (file == null) return; // cancelled
    await validateGarmentFile(slot, file);
  }

  /// Validate a specific file for [slot] (the seam the picker calls; also
  /// directly callable from tests).
  Future<void> validateGarmentFile(String slot, File file) async {
    if (!isVirtualTryOn || !vtoSlots.contains(slot)) return;
    _isValidatingGarment = true;
    _validatingGarmentSlot = slot;
    _garmentValidationError = null;
    notifyListeners();
    try {
      final inspection = await inspectVtoGarmentFile(file);
      _vtoCandidates[slot] = AdminVtoGarmentCandidate(
        file: file,
        slot: slot,
        sizeBytes: inspection.sizeBytes,
        sha256: inspection.sha256,
        contentType: inspection.contentType,
        width: inspection.width,
        height: inspection.height,
        targetVersion: _nextGarmentVersion(slot),
      );
      _stagedVtoDeletion = false;
      _vtoWorkflowNote = null;
      _hasUnsavedChanges = true;
    } on GarmentValidationException catch (e) {
      _garmentValidationError = e.message;
    } catch (_) {
      _garmentValidationError = 'This image could not be validated.';
    } finally {
      _isValidatingGarment = false;
      _validatingGarmentSlot = null;
      notifyListeners();
    }
  }

  void discardStagedGarment(String slot) {
    if (_vtoCandidates.remove(slot) == null) return;
    _garmentValidationError = null;
    _vtoWorkflowNote = null;
    _recomputeDirty();
    notifyListeners();
  }

  /// Stage switching the customer VTO entry point on/off. Only meaningful when
  /// a committed config exists.
  void setVtoEntryPointEnabled(bool enabled) {
    final product = _workingProduct;
    if (product == null || product.vtoMetadata == null) return;
    if (product.vtoDisabled == !enabled) return;
    _stage(product.copyWith(vtoDisabled: !enabled));
  }

  /// Stage a permanent deletion of the whole VTO config on Save. Guarded: the
  /// entry point must already be disabled when the product is customer-approved
  /// (see [canStageVtoDeletion]).
  void stageVtoDeletion() {
    if (!canStageVtoDeletion) return;
    _stagedVtoDeletion = true;
    _vtoCandidates.clear();
    _vtoGarmentCategory = null;
    _vtoWorkflowNote = null;
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void cancelStagedVtoDeletion() {
    if (!_stagedVtoDeletion) return;
    _stagedVtoDeletion = false;
    _recomputeDirty();
    notifyListeners();
  }

  int _nextGarmentVersion(String slot) {
    final committed = committedVtoAssetForSlot(slot);
    if (committed == null) return 1;
    return (committed.version < 1 ? 1 : committed.version) + 1;
  }

  /// The exact bytes of the committed garment asset for [slot], for the inline
  /// admin preview (`Image.memory`). Refuses (throws, never a Storage call)
  /// unless the stored path is **exactly this product's own** expected path for
  /// the slot — a well-formed but cross-product / hand-edited path is never
  /// downloaded.
  Future<Uint8List> downloadCommittedGarmentBytes(String slot) async {
    final asset = committedVtoAssetForSlot(slot);
    final product = _workingProduct;
    if (asset == null || product == null) {
      throw StateError('No committed garment image for "$slot".');
    }
    if (!asset.matchesExpectedPath(product.id, slot)) {
      throw StateError(
        'The stored garment path for "$slot" does not belong to this product — '
        'it will not be downloaded. Re-upload the image for this colour.',
      );
    }
    return _storage.downloadVtoGarmentBytes(asset.storagePath);
  }

  // ── save ──────────────────────────────────────────────────────────────

  /// General mode — the AR & Media screen owns the write. Uploads a staged
  /// GLB (if any), re-verifies it end-to-end, writes the resulting model to
  /// the database, and rolls the Storage object back on a Firestore failure.
  /// Returns `false` (keeping the staged candidate) on any failure.
  Future<bool> saveChanges() async {
    final database = _database;
    final product = selectedProduct;
    if (database == null || product == null) return false;

    if (isVirtualTryOn) return _saveVtoChanges(database, product);

    final candidate = _candidate;
    // Snapshot the previous committed model BEFORE the write — after
    // `updateProduct` the database no longer holds it, and we still need its
    // Storage path to clean up a superseded / deleted object.
    final previousModel = _committedProduct?.arMetadata;
    String? uploadedPath;
    try {
      ProductModel modelToSave = product;

      if (candidate != null) {
        final objectName = 'model-v${candidate.targetVersion}.glb';
        _isUploadingModel = true;
        _modelUploadProgress = 0;
        _modelValidationError = null;
        notifyListeners();

        uploadedPath = await _storage.uploadArModel(
          productId: product.id,
          objectName: objectName,
          file: candidate.file,
          provenance: _provenanceFor(candidate),
          onProgress: (p) {
            _modelUploadProgress = p;
            notifyListeners();
          },
        );

        // Re-verify what actually landed in Storage before trusting it — SHA,
        // structure and the bounding box against the captured dimensions.
        _isUploadingModel = false;
        notifyListeners();
        await _verifyCommittedBytes(uploadedPath, candidate);

        modelToSave = product.copyWith(
          arMetadata: candidate.toMetadata(storagePath: uploadedPath),
          arModelDisabled: false,
          clearArModelAssetPath: true,
          clearArScale: true,
        );
      } else if (_stagedModelDeletion) {
        modelToSave = product.copyWith(
          clearArMetadata: true,
          clearArModelAssetPath: true,
          clearArScale: true,
        );
      }

      await database.updateProduct(modelToSave);

      // Firestore write is committed — now clean up the superseded / deleted
      // Storage object. A failure here never fails the save (the metadata is
      // already correct), but for the *explicit delete* it is surfaced as an
      // honest "may need manual cleanup" note rather than a silent success.
      String? cleanupNote;
      if (candidate != null &&
          previousModel != null &&
          previousModel.storagePath != uploadedPath) {
        await _storage.deleteArModelByPath(previousModel.storagePath);
      } else if (_stagedModelDeletion && previousModel != null) {
        final removed = await _storage.deleteArModelByPath(
          previousModel.storagePath,
        );
        if (!removed) {
          cleanupNote =
              'The AR metadata was removed and customers can no longer launch '
              'this model, but its file could not be deleted from Storage — it '
              'may need manual cleanup in the Firebase console.';
        }
      }

      _workingProduct = modelToSave;
      _resetRoomArStaging();
      _modelWorkflowNote = cleanupNote;
      _hasUnsavedChanges = false;
      notifyListeners();
      return true;
    } on GlbValidationException catch (e) {
      await _rollbackUpload(uploadedPath);
      _isUploadingModel = false;
      _modelValidationError =
          'The uploaded model failed verification (${e.message}). '
          'Nothing was changed.';
      notifyListeners();
      return false;
    } catch (_) {
      await _rollbackUpload(uploadedPath);
      _isUploadingModel = false;
      _modelWorkflowNote =
          'Could not save AR & Media changes. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// The `twinArAr*` custom-metadata for an upload — byte-identical in shape
  /// to `scripts/upload_ar_models/`'s `objectMetadataFor`, so `storage.rules`
  /// can require the SHA key on every AR-object write.
  static Map<String, String> _provenanceFor(AdminArModelCandidate c) => {
    'twinArArModelSha256': c.sha256,
    'twinArArModelVersion': '${c.targetVersion}',
    'twinArArWidthM': '${c.widthM}',
    'twinArArDepthM': '${c.depthM}',
    'twinArArHeightM': '${c.heightM}',
    'twinArArScaleContract': ProductArMetadata.currentScaleContract,
  };

  Future<void> _verifyCommittedBytes(
    String storagePath,
    AdminArModelCandidate candidate,
  ) async {
    final bytes = await _storage.downloadArModelBytes(storagePath);
    final match = _inspector.inspect(
      bytes,
      expected: GlbExpectedBox(
        widthM: candidate.widthM,
        depthM: candidate.depthM,
        heightM: candidate.heightM,
      ),
      // Re-reading bytes already in Storage — the transport ceiling, not the
      // (stricter) authoring cap.
      maxBytes: kArModelTransportMaxBytes,
    );
    if (!match.ok) {
      throw GlbValidationException(
        match.rejectionReason ?? 'structure/bounding-box mismatch',
      );
    }
    // SHA-256 parity — the exact bytes we validated must be the exact bytes
    // now in Storage.
    final digest = _sha256Hex(bytes);
    if (digest != candidate.sha256) {
      throw const GlbValidationException('checksum mismatch after upload');
    }
  }

  Future<void> _rollbackUpload(String? uploadedPath) async {
    if (uploadedPath == null) return;
    try {
      await _storage.deleteArModelByPath(uploadedPath);
    } catch (_) {
      // Best-effort only.
    }
  }

  /// General mode — Virtual Try-On branch. Uploads every staged garment image,
  /// re-downloads and re-verifies each (SHA-256 + signature + dimensions),
  /// writes the merged [ProductVtoMetadata] to the database, then best-effort
  /// cleans up superseded objects. Rolls back every object uploaded this save
  /// on any failure; the staged candidates are kept for retry.
  Future<bool> _saveVtoChanges(
    CommerceDatabase database,
    ProductModel product,
  ) async {
    // Snapshot the committed config BEFORE the write — after `updateProduct`
    // the database no longer holds it and we still need its Storage paths.
    final previousVto = _committedProduct?.vtoMetadata ?? committedVtoMetadata;
    final uploaded = <String>[];
    try {
      if (_stagedVtoDeletion) {
        final modelToSave = product.copyWith(clearVtoMetadata: true);
        await database.updateProduct(modelToSave);
        final note = await _deleteAllVtoObjects(previousVto, product.id);
        _workingProduct = modelToSave;
        _resetVtoStaging();
        _vtoWorkflowNote = note;
        _hasUnsavedChanges = false;
        notifyListeners();
        return true;
      }

      final candidates = _vtoCandidates.values.toList();
      // A committed config whose slots no longer match `vtoSlots` (a colour was
      // removed) or whose paths look foreign needs reconciliation even when the
      // admin only toggled the entry point — fall through to the merge path so
      // stale metadata + orphaned owned objects are cleaned. A truly clean
      // toggle stays storage-free.
      final needsReconcile =
          previousVto != null &&
          _vtoMetadataNeedsReconcile(previousVto, product);
      if (candidates.isEmpty && !_vtoCategoryChanged && !needsReconcile) {
        await database.updateProduct(product);
        _workingProduct = product;
        _resetVtoStaging();
        _hasUnsavedChanges = false;
        notifyListeners();
        return true;
      }

      if (candidates.isNotEmpty) {
        _isUploadingGarment = true;
        _garmentUploadProgress = 0;
        _garmentValidationError = null;
        notifyListeners();
      }

      // Carry forward a committed slot ONLY when it is still an offered slot
      // (`vtoSlots`) AND its stored path is exactly this product's own path for
      // that slot. A removed-colour slot, a typo'd key, or a cross-product path
      // is pruned here (and its owned object cleaned after the write).
      final validSlots = vtoSlots.toSet();
      final newByColor = <String, VtoGarmentAsset>{};
      for (final e in (previousVto?.garmentsByColor ?? const {}).entries) {
        if (validSlots.contains(e.key) &&
            e.value.matchesExpectedPath(product.id, e.key)) {
          newByColor[e.key] = e.value;
        }
      }
      final prevDefault = previousVto?.garmentDefault;
      VtoGarmentAsset? newDefault =
          (prevDefault != null &&
              prevDefault.matchesExpectedPath(product.id, kVtoDefaultSlot))
          ? prevDefault
          : null;

      for (final c in candidates) {
        final objectName =
            'garment-${c.slot}-v${c.targetVersion}.${c.fileExtension}';
        final path = await _storage.uploadVtoGarment(
          productId: product.id,
          objectName: objectName,
          file: c.file,
          contentType: c.contentType,
          provenance: c.provenance(),
          onProgress: (p) {
            _garmentUploadProgress = p;
            notifyListeners();
          },
        );
        uploaded.add(path);
        await _verifyCommittedGarmentBytes(path, c);
        final asset = c.toAsset(storagePath: path);
        if (c.isDefaultSlot) {
          newDefault = asset;
        } else {
          newByColor[c.slot] = asset;
        }
      }

      _isUploadingGarment = false;
      notifyListeners();

      final merged = ProductVtoMetadata(
        garmentCategory: vtoGarmentCategory,
        garmentsByColor: Map.unmodifiable(newByColor),
        garmentDefault: newDefault,
      );
      final modelToSave = product.copyWith(
        vtoMetadata: merged,
        vtoDisabled: false,
      );

      await database.updateProduct(modelToSave);

      // Clean only objects that are provably this product's own and are no
      // longer referenced (removed colour, superseded version). Foreign paths
      // in the previous config are never touched — only flagged.
      final note = await _deleteSupersededVtoObjects(
        previousVto,
        product.id,
        merged.ownedAssetPaths(product.id),
      );

      _workingProduct = modelToSave;
      _resetVtoStaging();
      _vtoWorkflowNote = note;
      _hasUnsavedChanges = false;
      notifyListeners();
      return true;
    } on GarmentValidationException catch (e) {
      await _rollbackVtoUploads(uploaded);
      _isUploadingGarment = false;
      _garmentValidationError =
          'A garment image failed verification after upload (${e.message}). '
          'Nothing was changed.';
      notifyListeners();
      return false;
    } catch (_) {
      await _rollbackVtoUploads(uploaded);
      _isUploadingGarment = false;
      _vtoWorkflowNote =
          'Could not save Virtual Try-On changes. Please try again.';
      notifyListeners();
      return false;
    }
  }

  /// Re-verify the exact bytes now in Storage against the candidate that was
  /// validated locally — SHA-256 parity, signature, and pixel dimensions.
  Future<void> _verifyCommittedGarmentBytes(
    String storagePath,
    AdminVtoGarmentCandidate candidate,
  ) async {
    final bytes = await _storage.downloadVtoGarmentBytes(storagePath);
    if (_sha256Hex(bytes) != candidate.sha256) {
      throw const GarmentValidationException('checksum mismatch after upload');
    }
    final sniff = sniffVtoImageContentType(bytes);
    if (sniff == null || sniff != candidate.contentType) {
      throw const GarmentValidationException(
        'image format changed after upload',
      );
    }
    final dims = readVtoImageDimensions(bytes, sniff);
    if (dims == null ||
        dims.$1 != candidate.width ||
        dims.$2 != candidate.height) {
      throw const GarmentValidationException(
        'image dimensions changed after upload',
      );
    }
  }

  /// `true` when [previous] carries a slot that is no longer offered by
  /// [product] (a removed colour) or a path that does not belong to [product] —
  /// i.e. a save must rebuild + clean it even if the admin only toggled.
  bool _vtoMetadataNeedsReconcile(
    ProductVtoMetadata previous,
    ProductModel product,
  ) {
    final valid = vtoSlots.toSet();
    for (final e in previous.garmentsByColor.entries) {
      if (!valid.contains(e.key) ||
          !e.value.matchesExpectedPath(product.id, e.key)) {
        return true;
      }
    }
    final d = previous.garmentDefault;
    if (d != null && !d.matchesExpectedPath(product.id, kVtoDefaultSlot)) {
      return true;
    }
    return false;
  }

  /// Best-effort delete every **owned** ([ProductVtoMetadata.ownedAssetPaths])
  /// object in [previous] that [keepPaths] does not retain. A foreign path is
  /// never passed to Storage — it is only surfaced in the returned note.
  Future<String?> _deleteSupersededVtoObjects(
    ProductVtoMetadata? previous,
    String productId,
    Set<String> keepPaths,
  ) async {
    if (previous == null) return null;
    var anyFailed = false;
    for (final path in previous.ownedAssetPaths(productId)) {
      if (keepPaths.contains(path)) continue;
      if (!await _storage.deleteVtoGarmentByPath(path)) anyFailed = true;
    }
    final foreign = previous.hasForeignAssetPath(productId);
    if (!anyFailed && !foreign) return null;
    return 'The Virtual Try-On config was saved'
        '${anyFailed ? ', but a superseded garment image could not be removed '
                  'from Storage' : ''}'
        '${foreign ? '${anyFailed ? '; also' : ', but'} one or more stored '
                  'paths did not belong to this product and were left untouched' : ''}'
        ' — manual cleanup in the Firebase console may be needed.';
  }

  /// Best-effort delete every **owned** object in [previous]. Foreign paths are
  /// never touched, only flagged.
  Future<String?> _deleteAllVtoObjects(
    ProductVtoMetadata? previous,
    String productId,
  ) async {
    if (previous == null) return null;
    var anyFailed = false;
    for (final path in previous.ownedAssetPaths(productId)) {
      if (!await _storage.deleteVtoGarmentByPath(path)) anyFailed = true;
    }
    final foreign = previous.hasForeignAssetPath(productId);
    if (!anyFailed && !foreign) return null;
    return 'The Virtual Try-On metadata was removed and customers can no longer '
        'use try-on, but '
        '${anyFailed ? 'one or more garment image files could not be deleted '
                  'from Storage' : ''}'
        '${foreign ? '${anyFailed ? ' and ' : ''}one or more stored paths did '
                  'not belong to this product and were left untouched' : ''}'
        ' — manual cleanup in the Firebase console may be needed.';
  }

  Future<void> _rollbackVtoUploads(List<String> paths) async {
    for (final path in paths) {
      try {
        await _storage.deleteVtoGarmentByPath(path);
      } catch (_) {
        // Best-effort only.
      }
    }
  }

  /// Product-scoped mode — returns the working product carrying the staged
  /// change. A staged GLB rides along as `arModelAssetPath` = its local path
  /// (the "pending upload" channel, mirroring `ProductImageSource.file`) plus
  /// a placeholder `arMetadata`; `AdminProductFormViewModel` performs the
  /// upload on Save, when the real product id exists.
  ProductModel saveConfiguration() {
    final product = selectedProduct;
    if (product == null) {
      throw StateError('No product is available for AR configuration.');
    }
    _hasUnsavedChanges = false;
    if (isVirtualTryOn) {
      final staged = _stageVtoConfiguration(product);
      notifyListeners();
      return staged;
    }
    final candidate = _candidate;
    if (candidate != null) {
      // Placeholder storage path — the form recomputes it from the real id +
      // version at save. `arModelAssetPath` carries the local file to upload.
      final placeholder = candidate.toMetadata(
        storagePath:
            'products/${product.id}/ar/model-v${candidate.targetVersion}.glb',
      );
      final staged = product.copyWith(
        arMetadata: placeholder,
        arModelAssetPath: candidate.file.path,
        arScale: candidate.scale,
        arModelDisabled: false,
      );
      notifyListeners();
      return staged;
    }
    if (_stagedModelDeletion) {
      final staged = product.copyWith(
        clearArMetadata: true,
        clearArModelAssetPath: true,
        clearArScale: true,
      );
      notifyListeners();
      return staged;
    }
    notifyListeners();
    return product;
  }

  /// Product-scoped Virtual Try-On: bundle the staged changes onto the working
  /// product for `AdminProductFormViewModel` to persist. Each staged garment
  /// candidate rides along as a placeholder [VtoGarmentAsset] whose
  /// `storagePath` is its **local file path** (the "pending upload" channel);
  /// the form uploads and finalises them on Save once the real product id
  /// exists. A committed slot rides through ONLY when it is still an offered
  /// slot and its path belongs to this product — a removed colour / foreign
  /// path is not propagated (the form's own reconcile is the second layer).
  ProductModel _stageVtoConfiguration(ProductModel product) {
    if (_stagedVtoDeletion) {
      return product.copyWith(clearVtoMetadata: true);
    }
    if (_vtoCandidates.isEmpty && !_vtoCategoryChanged) {
      // Only a toggle (already on `product` via `_stage`) or nothing.
      return product;
    }
    final base = committedVtoMetadata;
    final validSlots = vtoSlots.toSet();
    final byColor = <String, VtoGarmentAsset>{};
    for (final e in (base?.garmentsByColor ?? const {}).entries) {
      if (validSlots.contains(e.key) &&
          e.value.matchesExpectedPath(product.id, e.key)) {
        byColor[e.key] = e.value;
      }
    }
    final baseDefault = base?.garmentDefault;
    VtoGarmentAsset? def =
        (baseDefault != null &&
            baseDefault.matchesExpectedPath(product.id, kVtoDefaultSlot))
        ? baseDefault
        : null;
    for (final c in _vtoCandidates.values) {
      final placeholder = c.toAsset(storagePath: c.file.path);
      if (c.isDefaultSlot) {
        def = placeholder;
      } else {
        byColor[c.slot] = placeholder;
      }
    }
    return product.copyWith(
      vtoMetadata: ProductVtoMetadata(
        garmentCategory: vtoGarmentCategory,
        garmentsByColor: Map.unmodifiable(byColor),
        garmentDefault: def,
      ),
      vtoDisabled: false,
    );
  }

  void discardChanges() {
    if (isProductScoped) {
      _hasUnsavedChanges = false;
      _resetRoomArStaging();
      _resetVtoStaging();
      notifyListeners();
      return;
    }
    final database = _database;
    if (database == null || _selectedProductId == null) return;
    _loadProduct(database.getProductById(_selectedProductId!));
    notifyListeners();
  }

  @override
  void dispose() {
    _database?.removeListener(_onDatabaseChanged);
    super.dispose();
  }
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
