import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_vto_metadata.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/admin/product_management/viewmodels/admin_product_form_viewmodel.dart';

import '../ar_media_management/vto_garment_test_support.dart';

class _ThrowingUpdateDatabase extends MockCommerceDatabase {
  @override
  Future<void> updateProduct(ProductModel product) =>
      Future.error(StateError('boom'));
}

void main() {
  late BuildContext ctx;
  late Directory tmp;

  Future<void> pumpContext(WidgetTester tester) => tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (c) {
          ctx = c;
          return const SizedBox();
        },
      ),
    ),
  );

  Future<void> drainToasts(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 350));
  }

  setUp(() => tmp = Directory.systemTemp.createTempSync('form_vto_test'));
  tearDown(() {
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  /// Seed a VTO product that already carries a committed contract.
  ProductModel seedConfiguredVtoProduct(MockCommerceDatabase db) {
    final base = db.getProductById('classic-blue-shirt'); // colour: black
    final configured = base.copyWith(
      vtoMetadata: ProductVtoMetadata(
        garmentCategory: 'top',
        garmentsByColor: {
          'black': VtoGarmentAsset(
            storagePath: 'products/classic-blue-shirt/vto/garment-black-v1.png',
            sha256: 'b' * 64,
            contentType: 'image/png',
            byteSize: 100,
            width: 900,
            height: 1200,
          ),
        },
      ),
    );
    db.updateProduct(configured);
    return configured;
  }

  testWidgets('editing a VTO product\'s title preserves its vtoMetadata', (
    tester,
  ) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    seedConfiguredVtoProduct(db);
    final storage = MockStorageService();
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'classic-blue-shirt',
    );
    vm.titleController.text = 'Classic Blue Shirt (Updated)';

    final ok = await vm.saveDraft(ctx);
    expect(ok, isTrue, reason: vm.categorySelectionBlockedReason ?? vm.error);

    final saved = db.getProductById('classic-blue-shirt');
    expect(saved.title, 'Classic Blue Shirt (Updated)');
    expect(saved.vtoMetadata, isNotNull);
    expect(saved.hasRenderableVtoAsset, isTrue);
    expect(storage.uploadedVtoGarmentPaths, isEmpty); // nothing re-uploaded
    await drainToasts(tester);
  });

  testWidgets('a staged local garment is uploaded + verified on save', (
    tester,
  ) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    final storage = MockStorageService();
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'classic-blue-shirt',
    );
    vm.descriptionController.text = 'A valid description for publish.';

    final local = writePng(tmp, 'black.png', width: 900, height: 1200);
    vm.applyArMediaConfiguration(
      vm.buildArConfigurationPreview().copyWith(
        vtoMetadata: ProductVtoMetadata(
          garmentCategory: 'top',
          garmentsByColor: {
            'black': VtoGarmentAsset(
              storagePath: local.path,
              sha256: 'c' * 64,
              contentType: 'image/png',
              byteSize: local.lengthSync(),
              width: 900,
              height: 1200,
            ),
          },
        ),
      ),
    );

    final ok = await vm.updateProduct(ctx);
    expect(ok, isTrue);

    expect(storage.uploadedVtoGarmentPaths, [
      'products/classic-blue-shirt/vto/garment-black-v1.png',
    ]);
    final saved = db.getProductById('classic-blue-shirt');
    expect(
      saved.vtoMetadata!.garmentsByColor['black']!.storagePath,
      'products/classic-blue-shirt/vto/garment-black-v1.png',
    );
    expect(saved.hasRenderableVtoAsset, isTrue);
    await drainToasts(tester);
  });

  testWidgets('a Firestore failure rolls back the uploaded garment object', (
    tester,
  ) async {
    await pumpContext(tester);
    final db = _ThrowingUpdateDatabase();
    final storage = MockStorageService();
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'classic-blue-shirt',
    );
    vm.descriptionController.text = 'A valid description for publish.';

    final local = writePng(tmp, 'black.png', width: 900, height: 1200);
    vm.applyArMediaConfiguration(
      vm.buildArConfigurationPreview().copyWith(
        vtoMetadata: ProductVtoMetadata(
          garmentCategory: 'top',
          garmentsByColor: {
            'black': VtoGarmentAsset(
              storagePath: local.path,
              sha256: 'c' * 64,
              contentType: 'image/png',
              byteSize: local.lengthSync(),
              width: 900,
              height: 1200,
            ),
          },
        ),
      ),
    );

    final ok = await vm.updateProduct(ctx);
    expect(ok, isFalse);
    expect(storage.uploadedVtoGarmentPaths, hasLength(1));
    expect(
      storage.deletedVtoGarmentPaths,
      contains(storage.uploadedVtoGarmentPaths.single),
    );
    await drainToasts(tester);
  });

  testWidgets('deleteProduct best-effort removes the product\'s VTO objects', (
    tester,
  ) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    seedConfiguredVtoProduct(db);
    final storage = MockStorageService();
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'classic-blue-shirt',
    );

    await vm.deleteProduct(ctx);

    expect(
      storage.deletedVtoGarmentPaths,
      contains('products/classic-blue-shirt/vto/garment-black-v1.png'),
    );
    expect(vm.vtoCleanupWarning, isNull);
    await drainToasts(tester);
  });

  testWidgets('deleteProduct surfaces a warning when VTO cleanup fails', (
    tester,
  ) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    seedConfiguredVtoProduct(db);
    final storage = MockStorageService()..failDeleteVtoGarment = true;
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'classic-blue-shirt',
    );

    await vm.deleteProduct(ctx);
    expect(vm.vtoCleanupWarning, contains('could not be removed from storage'));
    await drainToasts(tester);
  });

  testWidgets('switching experience away from VTO clears the staged contract', (
    tester,
  ) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: MockStorageService(),
    );
    vm.setCategory(
      MockCategoryRepository().categories.firstWhere(
        (c) => c.kind.name == 'clothing',
      ),
    );
    vm.setExperienceType(ProductExperienceType.virtualTryOn);
    vm.applyArMediaConfiguration(
      vm.buildArConfigurationPreview().copyWith(
        vtoMetadata: ProductVtoMetadata(
          garmentCategory: 'top',
          garmentDefault: VtoGarmentAsset(
            storagePath: '/tmp/x.png',
            sha256: 'd' * 64,
            contentType: 'image/png',
            byteSize: 1,
            width: 900,
            height: 1200,
          ),
        ),
      ),
    );
    expect(vm.vtoMetadata, isNotNull);

    vm.setExperienceType(ProductExperienceType.none);
    expect(vm.vtoMetadata, isNull);
    expect(vm.vtoDisabled, isFalse);
  });

  testWidgets('removing a colour prunes its stale slot + cleans its owned '
      'object on the next save', (tester) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    // mens-oxford-shirt has 4 colours (blue/gray/black/beige) + a garment for
    // two of them.
    final base = db.getProductById('mens-oxford-shirt');
    await db.updateProduct(
      base.copyWith(
        vtoMetadata: ProductVtoMetadata(
          garmentCategory: 'top',
          garmentsByColor: {
            'blue': VtoGarmentAsset(
              storagePath: 'products/mens-oxford-shirt/vto/garment-blue-v1.png',
              sha256: 'a' * 64,
              contentType: 'image/png',
              byteSize: 100,
              width: 900,
              height: 1200,
            ),
            'beige': VtoGarmentAsset(
              storagePath:
                  'products/mens-oxford-shirt/vto/garment-beige-v1.png',
              sha256: 'b' * 64,
              contentType: 'image/png',
              byteSize: 100,
              width: 900,
              height: 1200,
            ),
          },
        ),
      ),
    );
    final storage = MockStorageService();
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'mens-oxford-shirt',
    );
    // Admin removes the "beige" colour.
    vm.toggleColor(ProductColorOption.beige);
    expect(vm.availableColors.contains(ProductColorOption.beige), isFalse);

    expect(await vm.saveDraft(ctx), isTrue);

    final saved = db.getProductById('mens-oxford-shirt');
    expect(saved.vtoMetadata!.garmentsByColor.keys, ['blue']); // beige pruned
    expect(
      storage.deletedVtoGarmentPaths,
      contains('products/mens-oxford-shirt/vto/garment-beige-v1.png'),
    );
    expect(
      storage.deletedVtoGarmentPaths,
      isNot(contains('products/mens-oxford-shirt/vto/garment-blue-v1.png')),
    );
    await drainToasts(tester);
  });

  testWidgets('a foreign committed garment path is never deleted on product '
      'delete — only flagged', (tester) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    final base = db.getProductById('classic-blue-shirt');
    await db.updateProduct(
      base.copyWith(
        vtoMetadata: ProductVtoMetadata(
          garmentCategory: 'top',
          garmentsByColor: {
            'black': VtoGarmentAsset(
              storagePath:
                  'products/SOME-OTHER-PRODUCT/vto/garment-black-v1.png',
              sha256: 'a' * 64,
              contentType: 'image/png',
              byteSize: 100,
              width: 900,
              height: 1200,
            ),
          },
        ),
      ),
    );
    final storage = MockStorageService();
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'classic-blue-shirt',
    );

    await vm.deleteProduct(ctx);

    expect(storage.deletedVtoGarmentPaths, isEmpty); // foreign path untouched
    expect(vm.vtoCleanupWarning, contains('did not belong to this product'));
    await drainToasts(tester);
  });

  testWidgets('deleteProduct removes every owned Storage object — images, '
      'garments and the AR model — in one pass', (tester) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    final base = db.getProductById('classic-blue-shirt');
    await db.updateProduct(
      base.copyWith(
        mainImage: const ProductImageRef(
          path:
              'https://mock-storage.test/products/classic-blue-shirt/images/main.jpg',
          source: ProductImageSource.network,
        ),
        galleryMedia: const [
          ProductImageRef(
            path:
                'https://mock-storage.test/products/classic-blue-shirt/images/g1.jpg',
            source: ProductImageSource.network,
          ),
        ],
        arMetadata: ProductArMetadata(
          storagePath: 'products/classic-blue-shirt/ar/model-v1.glb',
          format: 'glb',
          modelVersion: '1',
          sha256: 'a' * 64,
          widthM: 0.5,
          depthM: 0.5,
          heightM: 0.9,
          scale: 1.0,
          scaleContract: ProductArMetadata.currentScaleContract,
        ),
        vtoMetadata: ProductVtoMetadata(
          garmentCategory: 'top',
          garmentsByColor: {
            'black': VtoGarmentAsset(
              storagePath:
                  'products/classic-blue-shirt/vto/garment-black-v1.png',
              sha256: 'b' * 64,
              contentType: 'image/png',
              byteSize: 100,
              width: 900,
              height: 1200,
            ),
          },
        ),
      ),
    );
    final storage = MockStorageService();
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'classic-blue-shirt',
    );

    await vm.deleteProduct(ctx);

    expect(db.products.any((p) => p.id == 'classic-blue-shirt'), isFalse);
    expect(
      storage.deletedArModelPaths,
      contains('products/classic-blue-shirt/ar/model-v1.glb'),
    );
    expect(
      storage.deletedVtoGarmentPaths,
      contains('products/classic-blue-shirt/vto/garment-black-v1.png'),
    );
    expect(
      storage.deletedOwnedProductImageUrls,
      containsAll(<String>[
        'https://mock-storage.test/products/classic-blue-shirt/images/main.jpg',
        'https://mock-storage.test/products/classic-blue-shirt/images/g1.jpg',
      ]),
    );
    expect(vm.arModelCleanupWarning, isNull);
    expect(vm.vtoCleanupWarning, isNull);
    expect(vm.imageCleanupWarning, isNull);
    await drainToasts(tester);
  });

  testWidgets('deleteProduct: a failed image cleanup warns but the Firestore '
      'delete still stands', (tester) async {
    await pumpContext(tester);
    final db = MockCommerceDatabase();
    final base = db.getProductById('classic-blue-shirt');
    await db.updateProduct(
      base.copyWith(
        mainImage: const ProductImageRef(
          path:
              'https://mock-storage.test/products/classic-blue-shirt/images/main.jpg',
          source: ProductImageSource.network,
        ),
        galleryMedia: const [],
      ),
    );
    final storage = MockStorageService()..failDeleteOwnedProductImage = true;
    final vm = AdminProductFormViewModel(
      database: db,
      categoryRepository: MockCategoryRepository(),
      storageService: storage,
      initialProductId: 'classic-blue-shirt',
    );

    await vm.deleteProduct(ctx);

    expect(db.products.any((p) => p.id == 'classic-blue-shirt'), isFalse);
    expect(
      vm.imageCleanupWarning,
      contains('could not be removed from storage'),
    );
    await drainToasts(tester);
  });
}
