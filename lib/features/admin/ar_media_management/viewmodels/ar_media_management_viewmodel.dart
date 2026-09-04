import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';

import '../../../../core/data/commerce_database.dart';
import '../../../../core/models/product/product_ar_metadata.dart';
import '../../../../core/models/product/product_color_option.dart';
import '../../../../core/models/product/product_experience_type.dart';
import '../../../../core/models/product/product_model.dart';
import '../../../../core/models/product/product_size.dart';
import '../../../../core/models/product/product_vto_model_type.dart';
import '../../../../core/services/firebase_storage_service.dart';
import '../../../../core/services/storage_service.dart';
import '../../../room_ar/model_delivery/glb_inspector.dart';
import '../../../room_ar/room_ar_product_manifest.dart';
import '../models/admin_ar_model_candidate.dart';
import '../services/ar_model_file_picker.dart';
import '../utils/admin_glb_validator.dart';

/// A mock media asset — **Virtual Try-On only** now. Room AR moved to real
/// GLB upload / validation / versioning in Phase 9.2 R16; VTO stays mock
/// until Phase 9.3+.
class MockMediaAsset {
  final String fileName;
  final String fileSize;

  const MockMediaAsset(this.fileName, this.fileSize);
}

enum MockBodyArea { upperBody, lowerBody, fullBody }

extension MockBodyAreaX on MockBodyArea {
  String get label => switch (this) {
    MockBodyArea.upperBody => 'Upper Body',
    MockBodyArea.lowerBody => 'Lower Body',
    MockBodyArea.fullBody => 'Full Body',
  };
}

enum ArMediaManagementMode { general, productScoped }

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
  /// product is not on the approved customer Room-AR list** (not in
  /// `RoomArProductManifest`, not in `storage.rules`' `isApprovedArProduct`).
  /// The model + metadata are valid, yet customers still cannot launch it:
  /// releasing a new product end-to-end (rules widen + manifest + a physical
  /// pass) is a separate Phase 9.2 step (§18). Shown honestly, never as "Live".
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
  final GlbInspector _inspector;

  /// Product-scoped mode only: the product exactly as it was handed in — the
  /// "what changed" baseline when there is no database to read from.
  final ProductModel? _initialProduct;

  ArMediaManagementViewModel(
    CommerceDatabase database, {
    StorageService? storageService,
    ArModelFilePicker? filePicker,
    GlbInspector inspector = const GlbInspector(),
  }) : this.general(
         database,
         storageService: storageService,
         filePicker: filePicker,
         inspector: inspector,
       );

  ArMediaManagementViewModel.general(
    CommerceDatabase database, {
    StorageService? storageService,
    ArModelFilePicker? filePicker,
    this._inspector = const GlbInspector(),
  }) : _database = database,
       _storage = storageService ?? FirebaseStorageService(),
       _picker = filePicker ?? const FilePickerArModelFilePicker(),
       _initialProduct = null,
       mode = ArMediaManagementMode.general {
    database.addListener(_onDatabaseChanged);
    _selectFirstEligibleProduct();
  }

  ArMediaManagementViewModel.productScoped(
    ProductModel product, {
    StorageService? storageService,
    ArModelFilePicker? filePicker,
    this._inspector = const GlbInspector(),
  }) : _database = null,
       _storage = storageService ?? FirebaseStorageService(),
       _picker = filePicker ?? const FilePickerArModelFilePicker(),
       _initialProduct = product,
       mode = ArMediaManagementMode.productScoped {
    _loadProduct(product);
  }

  static const vtoAssetOptions = [
    MockMediaAsset('male_jacket.glb', '9.1 MB'),
    MockMediaAsset('female_hoodie.glb', '8.7 MB'),
    MockMediaAsset('shirt_overlay.glb', '5.4 MB'),
  ];

  ProductModel? _workingProduct;
  String? _selectedProductId;
  bool _hasUnsavedChanges = false;

  String? get selectedProductId => _selectedProductId;
  ProductModel? get selectedProduct => _workingProduct;
  bool get isProductScoped => mode == ArMediaManagementMode.productScoped;
  bool get hasUnsavedChanges => _hasUnsavedChanges;

  // ── VTO mock state (unchanged) ─────────────────────────────────────────
  String _garmentType = 'Top';
  String get garmentType => _garmentType;

  MockBodyArea _bodyArea = MockBodyArea.upperBody;
  MockBodyArea get bodyArea => _bodyArea;

  ProductColorOption? _associatedColor;
  ProductColorOption? get associatedColor => _associatedColor;

  ProductSize? _associatedSize;
  ProductSize? get associatedSize => _associatedSize;

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

  bool get isVtoConfigured => selectedProduct?.vtoGarmentAssetPath != null;

  String? get vtoAssetFileName =>
      _fileNameFromPath(selectedProduct?.vtoGarmentAssetPath);

  String get vtoAssetFileSize =>
      _sizeFor(selectedProduct?.vtoGarmentAssetPath, vtoAssetOptions);

  /// `true` when the selected product is on the approved customer Room-AR
  /// list — `RoomArProductManifest` (kept in lockstep with `storage.rules`'
  /// `isApprovedArProduct` and the customer runtime's four-product gate). A
  /// valid model on a product that is *not* on this list is real, but no
  /// customer can launch it yet (§18).
  bool get productIsCustomerApproved =>
      RoomArProductManifest.byProductId.containsKey(_selectedProductId);

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
    _garmentType = 'Top';
    _bodyArea = MockBodyArea.upperBody;
    _associatedColor = product.availableColors.isEmpty
        ? null
        : product.availableColors.first;
    _associatedSize = product.availableSizes.isEmpty
        ? null
        : product.availableSizes.first;
    _hasUnsavedChanges = false;
    _resetRoomArStaging();
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
        (baseline != null &&
            _workingProduct != null &&
            (baseline.arModelDisabled != _workingProduct!.arModelDisabled ||
                baseline.vtoGarmentAssetPath !=
                    _workingProduct!.vtoGarmentAssetPath ||
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

  // ── VTO (unchanged mock behaviour) ────────────────────────────────────
  void selectVtoAsset(MockMediaAsset asset) {
    final product = selectedProduct;
    if (product == null || !isVirtualTryOn) return;
    _stage(product.copyWith(vtoGarmentAssetPath: asset.fileName));
  }

  void removeVtoAsset() {
    final product = selectedProduct;
    if (product == null ||
        !isVirtualTryOn ||
        product.vtoGarmentAssetPath == null) {
      return;
    }
    _stage(product.copyWith(clearVtoGarmentAssetPath: true));
  }

  void setGarmentType(String value) {
    if (_garmentType == value) return;
    _garmentType = value;
    _markFeatureStateDirty();
  }

  void setBodyArea(MockBodyArea value) {
    if (_bodyArea == value) return;
    _bodyArea = value;
    _markFeatureStateDirty();
  }

  void setAssociatedColor(ProductColorOption? value) {
    if (_associatedColor == value) return;
    _associatedColor = value;
    _markFeatureStateDirty();
  }

  void setAssociatedSize(ProductSize? value) {
    if (_associatedSize == value) return;
    _associatedSize = value;
    _markFeatureStateDirty();
  }

  void _markFeatureStateDirty() {
    _hasUnsavedChanges = true;
    notifyListeners();
  }

  void setVtoModelType(ProductVtoModelType value) {
    final product = selectedProduct;
    if (product == null || !isVirtualTryOn || product.vtoModelType == value) {
      return;
    }
    _stage(product.copyWith(vtoModelType: value));
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

  void discardChanges() {
    if (isProductScoped) {
      _hasUnsavedChanges = false;
      _resetRoomArStaging();
      notifyListeners();
      return;
    }
    final database = _database;
    if (database == null || _selectedProductId == null) return;
    _loadProduct(database.getProductById(_selectedProductId!));
    notifyListeners();
  }

  String _sizeFor(String? path, List<MockMediaAsset> options) {
    final name = _fileNameFromPath(path);
    if (name == null) return '';
    for (final option in options) {
      if (option.fileName == name) return option.fileSize;
    }
    return 'Mock local asset';
  }

  String? _fileNameFromPath(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    return path.split(RegExp(r'[/\\]')).last;
  }

  @override
  void dispose() {
    _database?.removeListener(_onDatabaseChanged);
    super.dispose();
  }
}

String _sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();
