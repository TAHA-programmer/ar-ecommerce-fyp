import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_vto_model_type.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/admin/ar_media_management/viewmodels/ar_media_management_viewmodel.dart';

import 'ar_glb_test_support.dart';

void main() {
  late MockCommerceDatabase database;
  late MockStorageService storage;
  late FakeArModelFilePicker picker;
  late Directory tmp;

  setUp(() {
    database = MockCommerceDatabase();
    storage = MockStorageService();
    picker = FakeArModelFilePicker();
    tmp = Directory.systemTemp.createTempSync('ar_media_vm_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ArMediaManagementViewModel general() => ArMediaManagementViewModel.general(
    database,
    storageService: storage,
    filePicker: picker,
  );

  // ── selection / eligibility (unchanged behaviour) ─────────────────────

  test('selector includes only Room AR and VTO products', () {
    final vm = general();
    addTearDown(vm.dispose);
    expect(vm.eligibleProducts, isNotEmpty);
    expect(
      vm.eligibleProducts.every(
        (p) => p.experienceType != ProductExperienceType.none,
      ),
      isTrue,
    );
  });

  // ── Room AR: pick + validate + stage ─────────────────────────────────

  test('a valid GLB for a model-less product stages as v1 with measured '
      'dimensions', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('velvet-armchair'); // roomAr, no committed model
    expect(vm.roomArModelStatus, AdminRoomArModelStatus.noModel);

    picker.next = writeBoxGlb(
      dir: tmp,
      name: 'armchair.glb',
      x: 0.80,
      y: 0.90,
      z: 0.85,
    );
    await vm.pickAndValidateModel();

    expect(vm.modelValidationError, isNull);
    final c = vm.stagedCandidate!;
    expect(c.targetVersion, 1);
    expect(c.widthM, closeTo(0.80, 0.01));
    expect(c.heightM, closeTo(0.90, 0.01));
    expect(c.depthM, closeTo(0.85, 0.01));
    expect(c.floorCentred, isTrue);
    expect(vm.roomArModelStatus, AdminRoomArModelStatus.stagedUpload);
    expect(vm.hasUnsavedChanges, isTrue);
  });

  test(
    'a non-GLB file is rejected with a message and nothing is staged',
    () async {
      final vm = general();
      addTearDown(vm.dispose);
      vm.selectProduct('velvet-armchair');
      picker.next = writeJunkFile(tmp, 'not-a-model.glb');
      await vm.pickAndValidateModel();
      expect(vm.stagedCandidate, isNull);
      expect(vm.modelValidationError, isNotNull);
    },
  );

  test('a model that is not floor-centred is rejected', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('velvet-armchair');
    picker.next = writeBoxGlb(dir: tmp, name: 'floating.glb', minY: 0.5);
    await vm.pickAndValidateModel();
    expect(vm.stagedCandidate, isNull);
    expect(vm.modelValidationError, contains('floor'));
  });

  test('cancelling the picker stages nothing and sets no error', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('velvet-armchair');
    picker.next = null;
    await vm.pickAndValidateModel();
    expect(vm.stagedCandidate, isNull);
    expect(vm.modelValidationError, isNull);
  });

  // ── save: upload + verify + write + supersede ────────────────────────

  test('saving a staged model uploads model-v1, verifies it and writes a '
      'renderable contract', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('velvet-armchair');
    picker.next = writeBoxGlb(dir: tmp, name: 'armchair.glb');
    await vm.pickAndValidateModel();

    expect(await vm.saveChanges(), isTrue);

    expect(
      storage.uploadedArModelPaths,
      contains('products/velvet-armchair/ar/model-v1.glb'),
    );
    final saved = database.getProductById('velvet-armchair');
    expect(saved.arMetadata, isNotNull);
    expect(
      saved.arMetadata!.storagePath,
      'products/velvet-armchair/ar/model-v1.glb',
    );
    expect(saved.arMetadata!.modelVersion, '1');
    expect(saved.arMetadata!.isRenderable, isTrue);
    expect(saved.hasRenderableArModel, isTrue);
    expect(saved.arModelDisabled, isFalse);
    expect(vm.stagedCandidate, isNull);
    expect(vm.hasUnsavedChanges, isFalse);
  });

  test('replacing an existing model uploads v2 and deletes the old v1 only '
      'after the Firestore write', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('luna-accent-chair'); // seeded with a committed v1
    expect(vm.roomArModelStatus, AdminRoomArModelStatus.live);

    picker.next = writeBoxGlb(
      dir: tmp,
      name: 'chair-v2.glb',
      x: 0.70,
      y: 0.82,
      z: 0.72,
    );
    await vm.pickAndValidateModel();
    expect(vm.stagedCandidate!.targetVersion, 2);

    expect(await vm.saveChanges(), isTrue);
    expect(
      storage.uploadedArModelPaths,
      contains('products/luna-accent-chair/ar/model-v2.glb'),
    );
    expect(
      storage.deletedArModelPaths,
      contains('products/luna-accent-chair/ar/model-v1.glb'),
    );
    final saved = database.getProductById('luna-accent-chair');
    expect(saved.arMetadata!.modelVersion, '2');
  });

  test('a Firestore failure rolls the just-uploaded object back and keeps the '
      'candidate staged', () async {
    final throwingDb = _ThrowingUpdateDatabase();
    final vm = ArMediaManagementViewModel.general(
      throwingDb,
      storageService: storage,
      filePicker: picker,
    );
    addTearDown(vm.dispose);
    vm.selectProduct('velvet-armchair');
    picker.next = writeBoxGlb(dir: tmp, name: 'armchair.glb');
    await vm.pickAndValidateModel();

    expect(await vm.saveChanges(), isFalse);
    expect(storage.uploadedArModelPaths, hasLength(1));
    expect(
      storage.deletedArModelPaths,
      contains(storage.uploadedArModelPaths.first),
    );
    expect(vm.stagedCandidate, isNotNull); // still staged for a retry
  });

  // ── enable / disable the customer entry point ────────────────────────

  test(
    'disabling the entry point retains the model and is storage-free',
    () async {
      final vm = general();
      addTearDown(vm.dispose);
      vm.selectProduct('luna-accent-chair');
      vm.setRoomArEntryPointEnabled(false);
      expect(vm.roomArModelStatus, AdminRoomArModelStatus.stagedToggle);

      expect(await vm.saveChanges(), isTrue);
      final saved = database.getProductById('luna-accent-chair');
      expect(saved.arModelDisabled, isTrue);
      expect(saved.arMetadata, isNotNull);
      expect(saved.hasRenderableArModel, isFalse);
      expect(saved.hasDisabledArModel, isTrue);
      expect(storage.uploadedArModelPaths, isEmpty);
      expect(storage.deletedArModelPaths, isEmpty);

      // re-enable
      vm.setRoomArEntryPointEnabled(true);
      expect(await vm.saveChanges(), isTrue);
      expect(
        database.getProductById('luna-accent-chair').arModelDisabled,
        isFalse,
      );
    },
  );

  // ── explicit delete workflow ─────────────────────────────────────────

  test('delete is blocked until the entry point is disabled, then removes '
      'the object and the contract', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('luna-accent-chair');

    expect(vm.canStageModelDeletion, isFalse); // entry point still on
    vm.stageModelDeletion();
    expect(vm.roomArModelStatus, isNot(AdminRoomArModelStatus.stagedDeletion));

    // disable + save first
    vm.setRoomArEntryPointEnabled(false);
    await vm.saveChanges();
    expect(vm.canStageModelDeletion, isTrue);

    vm.stageModelDeletion();
    expect(vm.roomArModelStatus, AdminRoomArModelStatus.stagedDeletion);
    expect(await vm.saveChanges(), isTrue);

    final saved = database.getProductById('luna-accent-chair');
    expect(saved.arMetadata, isNull);
    expect(saved.arModelDisabled, isFalse);
    expect(saved.experienceType, ProductExperienceType.roomAr);
    expect(
      storage.deletedArModelPaths,
      contains('products/luna-accent-chair/ar/model-v1.glb'),
    );
  });

  test('an explicit delete whose Storage removal fails still succeeds but '
      'sets an honest workflow note', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('luna-accent-chair');
    vm.setRoomArEntryPointEnabled(false);
    await vm.saveChanges();

    storage.failDeleteArModel = true;
    vm.stageModelDeletion();
    expect(await vm.saveChanges(), isTrue);

    expect(database.getProductById('luna-accent-chair').arMetadata, isNull);
    expect(vm.modelWorkflowNote, isNotNull);
    expect(vm.modelWorkflowNote, contains('manual cleanup'));
  });

  test('every upload carries twinArAr* provenance metadata', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('velvet-armchair');
    picker.next = writeBoxGlb(
      dir: tmp,
      name: 'armchair.glb',
      x: 0.8,
      y: 0.9,
      z: 0.85,
    );
    await vm.pickAndValidateModel();
    await vm.saveChanges();

    final p = storage.lastArModelProvenance!;
    expect(p['twinArArModelSha256'], matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(p['twinArArModelVersion'], '1');
    expect(p['twinArArScaleContract'], 'twin-ar/scale-contract-9.2.2');
    expect(p.containsKey('twinArArWidthM'), isTrue);
  });

  // ── honest status for a product not on the approved customer list ────

  test('a valid model on a NON-approved product shows readyNotApproved, '
      'never "live"', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('velvet-armchair'); // roomAr, NOT in RoomArProductManifest
    picker.next = writeBoxGlb(
      dir: tmp,
      name: 'armchair.glb',
      x: 0.8,
      y: 0.9,
      z: 0.85,
    );
    await vm.pickAndValidateModel();
    expect(await vm.saveChanges(), isTrue);

    expect(vm.productIsCustomerApproved, isFalse);
    expect(vm.roomArModelStatus, AdminRoomArModelStatus.readyNotApproved);
    // the model contract itself is valid…
    expect(
      database.getProductById('velvet-armchair').arMetadata!.isRenderable,
      isTrue,
    );
  });

  test('an approved product with a valid enabled model shows live', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('luna-accent-chair');
    expect(vm.productIsCustomerApproved, isTrue);
    expect(vm.roomArModelStatus, AdminRoomArModelStatus.live);
  });

  // ── product-scoped mode ─────────────────────────────────────────────

  test('product-scoped save returns a staged contract + local upload path, '
      'never writing to the database', () async {
    final draft = database
        .getProductById('velvet-armchair')
        .copyWith(id: '__unsaved_product__', sku: 'Generated when saved');
    final scoped = ArMediaManagementViewModel.productScoped(
      draft,
      storageService: storage,
      filePicker: picker,
    );
    addTearDown(scoped.dispose);

    final before = database.products.length;
    picker.next = writeBoxGlb(dir: tmp, name: 'scoped.glb');
    await scoped.pickAndValidateModel();
    final result = scoped.saveConfiguration();

    expect(result.arMetadata, isNotNull);
    expect(
      result.arModelAssetPath,
      picker.next!.path,
    ); // pending-upload channel
    expect(database.products.length, before);
    expect(storage.uploadedArModelPaths, isEmpty);
  });

  // ── VTO stays mock (unchanged) ──────────────────────────────────────

  test('VTO asset selection, replace and remove are unchanged', () {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('mens-oxford-shirt');
    vm.selectVtoAsset(ArMediaManagementViewModel.vtoAssetOptions.first);
    expect(vm.selectedProduct!.vtoGarmentAssetPath, 'male_jacket.glb');
    vm.setVtoModelType(ProductVtoModelType.female);
    vm.saveChanges();
    final saved = database.getProductById('mens-oxford-shirt');
    expect(saved.vtoGarmentAssetPath, 'male_jacket.glb');
    expect(saved.vtoModelType, ProductVtoModelType.female);
  });
}

class _ThrowingUpdateDatabase extends MockCommerceDatabase {
  @override
  Future<void> updateProduct(ProductModel product) =>
      Future.error(StateError('boom'));
}
