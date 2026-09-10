import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_publication_status.dart';
import 'package:twin_ar/core/models/product/product_vto_metadata.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/admin/ar_media_management/viewmodels/ar_media_management_viewmodel.dart';

import 'ar_glb_test_support.dart';
import 'vto_garment_test_support.dart';

void main() {
  late MockCommerceDatabase database;
  late MockStorageService storage;
  late FakeArModelFilePicker picker;
  late FakeVtoGarmentFilePicker vtoPicker;
  late Directory tmp;

  setUp(() {
    database = MockCommerceDatabase();
    storage = MockStorageService();
    picker = FakeArModelFilePicker();
    vtoPicker = FakeVtoGarmentFilePicker();
    tmp = Directory.systemTemp.createTempSync('ar_media_vm_test');
  });

  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  ArMediaManagementViewModel general() => ArMediaManagementViewModel.general(
    database,
    storageService: storage,
    filePicker: picker,
    vtoFilePicker: vtoPicker,
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
    vm.selectProduct('other-product-3'); // roomAr, no committed model
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
      vm.selectProduct('other-product-3');
      picker.next = writeJunkFile(tmp, 'not-a-model.glb');
      await vm.pickAndValidateModel();
      expect(vm.stagedCandidate, isNull);
      expect(vm.modelValidationError, isNotNull);
    },
  );

  test('a model that is not floor-centred is rejected', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('other-product-3');
    picker.next = writeBoxGlb(dir: tmp, name: 'floating.glb', minY: 0.5);
    await vm.pickAndValidateModel();
    expect(vm.stagedCandidate, isNull);
    expect(vm.modelValidationError, contains('floor'));
  });

  test('cancelling the picker stages nothing and sets no error', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('other-product-3');
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
    vm.selectProduct('other-product-3');
    picker.next = writeBoxGlb(dir: tmp, name: 'armchair.glb');
    await vm.pickAndValidateModel();

    expect(await vm.saveChanges(), isTrue);

    expect(
      storage.uploadedArModelPaths,
      contains('products/other-product-3/ar/model-v1.glb'),
    );
    final saved = database.getProductById('other-product-3');
    expect(saved.arMetadata, isNotNull);
    expect(
      saved.arMetadata!.storagePath,
      'products/other-product-3/ar/model-v1.glb',
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
    vm.selectProduct('other-product-3');
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
    vm.selectProduct('other-product-3');
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

  // ── honest status for a product not yet customer-visible ─────────────
  // Phase 9.2 §17-follow-up: `productIsCustomerApproved` is no longer tied
  // to `RoomArProductManifest` (a static list) — it now mirrors
  // `storage.rules`' own dynamic, metadata-driven check: published + active
  // + a renderable, enabled `ar*` contract. So "not yet approved" now means
  // "not yet published/active", not "missing from a manifest".

  test('a valid model on an unpublished (draft) product shows '
      'readyNotApproved, never "live"', () async {
    await database.updateProduct(
      database
          .getProductById('other-product-3')
          .copyWith(publicationStatus: ProductPublicationStatus.draft),
    );
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('other-product-3'); // roomAr, draft
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
      database.getProductById('other-product-3').arMetadata!.isRenderable,
      isTrue,
    );
  });

  test('a valid model on an inactive product shows readyNotApproved, '
      'never "live"', () async {
    await database.updateProduct(
      database.getProductById('other-product-3').copyWith(isActive: false),
    );
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('other-product-3'); // roomAr, inactive
    picker.next = writeBoxGlb(dir: tmp, name: 'armchair.glb');
    await vm.pickAndValidateModel();
    expect(await vm.saveChanges(), isTrue);

    expect(vm.productIsCustomerApproved, isFalse);
    expect(vm.roomArModelStatus, AdminRoomArModelStatus.readyNotApproved);
  });

  test('a valid model on a published, active, genuinely NEW product id — '
      'never registered in RoomArProductManifest — shows "live"', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('other-product-3'); // roomAr, published + active
    picker.next = writeBoxGlb(dir: tmp, name: 'armchair.glb');
    await vm.pickAndValidateModel();
    expect(await vm.saveChanges(), isTrue);

    // No RoomArProductManifest entry exists for this id anywhere in the
    // codebase — approval is now purely metadata-driven.
    expect(vm.productIsCustomerApproved, isTrue);
    expect(vm.roomArModelStatus, AdminRoomArModelStatus.live);
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
        .getProductById('other-product-3')
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

  // ── VTO: production garment pipeline (Phase 9.3 Stage 3) ────────────

  test('selecting a VTO product exposes one slot per colour + default', () {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('mens-oxford-shirt'); // blue/gray/black/beige
    expect(vm.isVirtualTryOn, isTrue);
    expect(vm.vtoSlots, ['blue', 'gray', 'black', 'beige', 'default']);
    expect(vm.vtoSlots.last, 'default');
    expect(vm.vtoAssetStatus, AdminVtoAssetStatus.noAsset);

    final single = general();
    addTearDown(single.dispose);
    single.selectProduct('classic-blue-shirt'); // single colour: black
    expect(single.vtoSlots, ['black', 'default']);
  });

  test('pick → validate → stage a garment for a colour slot', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('mens-oxford-shirt');
    vtoPicker.next = writePng(tmp, 'black.png', width: 900, height: 1200);
    await vm.pickAndValidateGarment('black');

    final c = vm.vtoCandidateForSlot('black');
    expect(c, isNotNull);
    expect(c!.contentType, 'image/png');
    expect(c.targetVersion, 1);
    expect(vm.vtoAssetStatus, AdminVtoAssetStatus.stagedUpload);
    expect(vm.hasUnsavedChanges, isTrue);
  });

  test('an invalid garment image sets the error and stages nothing', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('mens-oxford-shirt');
    vtoPicker.next = writeFakeImage(tmp, 'junk.png');
    await vm.pickAndValidateGarment('black');
    expect(vm.vtoCandidateForSlot('black'), isNull);
    expect(vm.garmentValidationError, isNotNull);
  });

  test(
    'save uploads, re-verifies and writes a renderable VTO contract',
    () async {
      final vm = general();
      addTearDown(vm.dispose);
      vm.selectProduct('classic-blue-shirt');
      vm.setVtoGarmentCategory('top');
      vtoPicker.next = writePng(tmp, 'g.png', width: 900, height: 1200);
      await vm.pickAndValidateGarment('black');

      expect(await vm.saveChanges(), isTrue);

      expect(storage.uploadedVtoGarmentPaths, [
        'products/classic-blue-shirt/vto/garment-black-v1.png',
      ]);
      expect(storage.lastVtoGarmentContentType, 'image/png');
      expect(storage.lastVtoGarmentProvenance!['twinArVtoSha256'], isNotNull);

      final saved = database.getProductById('classic-blue-shirt');
      expect(saved.vtoMetadata, isNotNull);
      expect(saved.vtoMetadata!.garmentCategory, 'top');
      expect(saved.hasRenderableVtoAsset, isTrue);
      expect(vm.vtoAssetStatus, AdminVtoAssetStatus.live);
    },
  );

  test('a Firestore failure rolls back the uploaded garment object', () async {
    final failDb = _ThrowingUpdateDatabase();
    final vm = ArMediaManagementViewModel.general(
      failDb,
      storageService: storage,
      filePicker: picker,
      vtoFilePicker: vtoPicker,
    );
    addTearDown(vm.dispose);
    vm.selectProduct('classic-blue-shirt');
    vtoPicker.next = writePng(tmp, 'g.png', width: 900, height: 1200);
    await vm.pickAndValidateGarment('black');

    expect(await vm.saveChanges(), isFalse);
    expect(storage.uploadedVtoGarmentPaths, hasLength(1));
    expect(
      storage.deletedVtoGarmentPaths,
      contains(storage.uploadedVtoGarmentPaths.single),
    );
    // Candidate kept for retry.
    expect(vm.vtoCandidateForSlot('black'), isNotNull);
  });

  test('replace bumps the version and cleans the superseded object', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('classic-blue-shirt');
    vtoPicker.next = writePng(tmp, 'v1.png', width: 900, height: 1200);
    await vm.pickAndValidateGarment('black');
    await vm.saveChanges();

    vtoPicker.next = writePng(tmp, 'v2.png', width: 1000, height: 1300);
    await vm.pickAndValidateGarment('black');
    expect(vm.vtoCandidateForSlot('black')!.targetVersion, 2);
    await vm.saveChanges();

    expect(
      storage.uploadedVtoGarmentPaths,
      containsAll([
        'products/classic-blue-shirt/vto/garment-black-v1.png',
        'products/classic-blue-shirt/vto/garment-black-v2.png',
      ]),
    );
    expect(
      storage.deletedVtoGarmentPaths,
      contains('products/classic-blue-shirt/vto/garment-black-v1.png'),
    );
    final saved = database.getProductById('classic-blue-shirt');
    expect(saved.vtoMetadata!.garmentsByColor['black']!.version, 2);
  });

  test(
    'disable → re-enable is storage-free and toggles the entry point',
    () async {
      final vm = general();
      addTearDown(vm.dispose);
      vm.selectProduct('classic-blue-shirt');
      vtoPicker.next = writePng(tmp, 'g.png', width: 900, height: 1200);
      await vm.pickAndValidateGarment('black');
      await vm.saveChanges();

      vm.setVtoEntryPointEnabled(false);
      expect(vm.vtoAssetStatus, AdminVtoAssetStatus.stagedToggle);
      expect(await vm.saveChanges(), isTrue);
      expect(storage.uploadedVtoGarmentPaths, hasLength(1)); // no new upload
      expect(database.getProductById('classic-blue-shirt').vtoDisabled, isTrue);
      expect(vm.vtoAssetStatus, AdminVtoAssetStatus.disabled);

      vm.setVtoEntryPointEnabled(true);
      await vm.saveChanges();
      expect(
        database.getProductById('classic-blue-shirt').vtoDisabled,
        isFalse,
      );
    },
  );

  test(
    'delete is guarded (disable first) then removes every VTO object',
    () async {
      final vm = general();
      addTearDown(vm.dispose);
      vm.selectProduct('classic-blue-shirt');
      vtoPicker.next = writePng(tmp, 'g.png', width: 900, height: 1200);
      await vm.pickAndValidateGarment('black');
      await vm.saveChanges();

      // Guard: cannot stage a deletion while customer-approved + enabled.
      expect(vm.canStageVtoDeletion, isFalse);
      vm.stageVtoDeletion();
      expect(vm.vtoAssetStatus, isNot(AdminVtoAssetStatus.stagedDeletion));

      vm.setVtoEntryPointEnabled(false);
      await vm.saveChanges();
      expect(vm.canStageVtoDeletion, isTrue);
      vm.stageVtoDeletion();
      expect(vm.vtoAssetStatus, AdminVtoAssetStatus.stagedDeletion);
      expect(await vm.saveChanges(), isTrue);

      expect(
        storage.deletedVtoGarmentPaths,
        contains('products/classic-blue-shirt/vto/garment-black-v1.png'),
      );
      expect(database.getProductById('classic-blue-shirt').vtoMetadata, isNull);
      expect(
        database.getProductById('classic-blue-shirt').vtoDisabled,
        isFalse,
      );
    },
  );

  test('a cross-product garment path never reads as renderable', () async {
    final vm = general();
    addTearDown(vm.dispose);
    vm.selectProduct('classic-blue-shirt');
    vtoPicker.next = writePng(tmp, 'g.png', width: 900, height: 1200);
    await vm.pickAndValidateGarment('black');
    await vm.saveChanges();

    // Hand-corrupt the committed metadata to point at another product.
    final tampered = database
        .getProductById('classic-blue-shirt')
        .copyWith(
          vtoMetadata: ProductVtoMetadata(
            garmentCategory: 'top',
            garmentsByColor: {
              'black': const VtoGarmentAsset(
                storagePath: 'products/OTHER/vto/garment-black-v1.png',
                sha256:
                    '0123456789abcdef0123456789abcdef'
                    '0123456789abcdef0123456789abcdef',
                contentType: 'image/png',
                byteSize: 100,
                width: 900,
                height: 1200,
              ),
            },
          ),
        );
    await database.updateProduct(tampered);
    expect(tampered.hasRenderableVtoAsset, isFalse);
  });

  group('foreign-path guard (Stage 3 hardening)', () {
    /// A `classic-blue-shirt` whose committed `black` slot points at another
    /// product's Storage object (corrupted / hand-edited Firestore doc).
    Future<ArMediaManagementViewModel> withForeignBlackSlot() async {
      final vm = general();
      addTearDown(vm.dispose);
      final tampered = database
          .getProductById('classic-blue-shirt')
          .copyWith(
            vtoMetadata: ProductVtoMetadata(
              garmentCategory: 'top',
              garmentsByColor: {
                'black': VtoGarmentAsset(
                  storagePath: 'products/OTHER/vto/garment-black-v1.png',
                  sha256: 'a' * 64,
                  contentType: 'image/png',
                  byteSize: 100,
                  width: 900,
                  height: 1200,
                ),
              },
            ),
          );
      await database.updateProduct(tampered);
      vm.selectProduct('classic-blue-shirt');
      return vm;
    }

    test('preview refuses a foreign path — no Storage download', () async {
      final vm = await withForeignBlackSlot();
      expect(vm.committedGarmentPathIsForeign('black'), isTrue);
      expect(vm.canPreviewCommittedGarment('black'), isFalse);
      await expectLater(
        vm.downloadCommittedGarmentBytes('black'),
        throwsA(isA<StateError>()),
      );
      expect(storage.vtoGarmentBytesByPath.keys, isEmpty);
    });

    test(
      'replacing over a foreign slot never deletes the foreign object',
      () async {
        final vm = await withForeignBlackSlot();
        vtoPicker.next = writePng(tmp, 'new.png', width: 900, height: 1200);
        await vm.pickAndValidateGarment('black');
        expect(await vm.saveChanges(), isTrue);

        // The new owned object is written (version bumped off the foreign v1);
        // the foreign one is never touched.
        expect(storage.uploadedVtoGarmentPaths, [
          'products/classic-blue-shirt/vto/garment-black-v2.png',
        ]);
        expect(
          storage.deletedVtoGarmentPaths,
          isNot(contains('products/OTHER/vto/garment-black-v1.png')),
        );
        final saved = database.getProductById('classic-blue-shirt');
        expect(
          saved.vtoMetadata!.garmentsByColor['black']!.storagePath,
          'products/classic-blue-shirt/vto/garment-black-v2.png',
        );
        expect(saved.hasRenderableVtoAsset, isTrue);
        // The foreign residue is disclosed, not hidden.
        expect(vm.vtoWorkflowNote, contains('did not belong to this product'));
      },
    );

    test(
      'config removal never deletes a foreign object, only flags it',
      () async {
        final vm = await withForeignBlackSlot();
        // Not customer-approved (foreign path → not renderable) so deletion can
        // be staged directly.
        vm.stageVtoDeletion();
        expect(vm.vtoAssetStatus, AdminVtoAssetStatus.stagedDeletion);
        expect(await vm.saveChanges(), isTrue);

        expect(storage.deletedVtoGarmentPaths, isEmpty);
        expect(vm.vtoWorkflowNote, contains('did not belong to this product'));
        expect(
          database.getProductById('classic-blue-shirt').vtoMetadata,
          isNull,
        );
      },
    );
  });

  test(
    'removing a colour prunes its stale slot + cleans its owned object',
    () async {
      final vm = general();
      addTearDown(vm.dispose);
      // Seed a 2-colour product with both garments committed + owned.
      final base = database.getProductById('classic-blue-shirt');
      final twoColour = base.copyWith(
        availableColors: const {
          ProductColorOption.black,
          ProductColorOption.blue,
        },
        vtoMetadata: ProductVtoMetadata(
          garmentCategory: 'top',
          garmentsByColor: {
            'black': VtoGarmentAsset(
              storagePath:
                  'products/classic-blue-shirt/vto/garment-black-v1.png',
              sha256: 'a' * 64,
              contentType: 'image/png',
              byteSize: 100,
              width: 900,
              height: 1200,
            ),
            'blue': VtoGarmentAsset(
              storagePath:
                  'products/classic-blue-shirt/vto/garment-blue-v1.png',
              sha256: 'b' * 64,
              contentType: 'image/png',
              byteSize: 100,
              width: 900,
              height: 1200,
            ),
          },
        ),
      );
      await database.updateProduct(twoColour);
      // Now the product drops the "blue" colour.
      await database.updateProduct(
        database
            .getProductById('classic-blue-shirt')
            .copyWith(availableColors: const {ProductColorOption.black}),
      );

      vm.selectProduct('classic-blue-shirt');
      expect(vm.vtoSlots, ['black', 'default']);
      // A category change is enough to trigger a content save.
      vm.setVtoGarmentCategory('outerwear');
      expect(await vm.saveChanges(), isTrue);

      final saved = database.getProductById('classic-blue-shirt');
      expect(saved.vtoMetadata!.garmentsByColor.keys, ['black']); // blue pruned
      expect(
        storage.deletedVtoGarmentPaths,
        contains('products/classic-blue-shirt/vto/garment-blue-v1.png'),
      );
      expect(
        storage.deletedVtoGarmentPaths,
        isNot(contains('products/classic-blue-shirt/vto/garment-black-v1.png')),
      );
    },
  );

  test(
    'product-scoped save carries staged garments as local-path placeholders',
    () {
      final draft = database
          .getProductById('classic-blue-shirt')
          .copyWith(id: '__unsaved_product__', sku: 'Generated when saved');
      final scoped = ArMediaManagementViewModel.productScoped(
        draft,
        storageService: storage,
        filePicker: picker,
        vtoFilePicker: vtoPicker,
      );
      addTearDown(scoped.dispose);

      final before = database.products.length;
      vtoPicker.next = writePng(tmp, 'scoped.png', width: 900, height: 1200);
      return scoped.pickAndValidateGarment('black').then((_) {
        final result = scoped.saveConfiguration();
        expect(result.vtoMetadata, isNotNull);
        expect(
          result.vtoMetadata!.garmentsByColor['black']!.storagePath,
          vtoPicker.next!.path,
        );
        expect(database.products.length, before);
        expect(storage.uploadedVtoGarmentPaths, isEmpty);
      });
    },
  );
}

class _ThrowingUpdateDatabase extends MockCommerceDatabase {
  @override
  Future<void> updateProduct(ProductModel product) =>
      Future.error(StateError('boom'));
}
