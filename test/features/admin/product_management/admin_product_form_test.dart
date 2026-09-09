import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/core/data/category_repository.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/category/commerce_category_model.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_publication_status.dart';
import 'package:twin_ar/features/admin/product_management/viewmodels/admin_product_form_viewmodel.dart';
import 'package:twin_ar/features/admin/product_management/views/admin_product_form_view.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_vto_model_type.dart';
import 'package:twin_ar/app/routes/app_router.dart';
import 'package:twin_ar/core/models/product/product_ar_metadata.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/core/services/storage_service.dart';
import 'package:twin_ar/features/admin/ar_media_management/views/admin_ar_media_management_view.dart';

import '../ar_media_management/ar_glb_test_support.dart';

void main() {
  late MockCommerceDatabase db;
  late MockCategoryRepository categoryRepo;
  late MockStorageService storage;

  setUp(() {
    db = MockCommerceDatabase();
    categoryRepo = MockCategoryRepository();
    storage = MockStorageService();
  });

  CommerceCategoryModel categoryOf(String categoryId) =>
      categoryRepo.categories.firstWhere((c) => c.categoryId == categoryId);

  Widget buildApp({String? productId}) {
    // Providers ABOVE MaterialApp so routes pushed by onGenerateRoute
    // (e.g. adminArMedia) can also read them — mirrors AppProviders wrapping
    // MaterialApp in the real app.
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CommerceDatabase>.value(value: db),
        ChangeNotifierProvider<CategoryRepository>.value(value: categoryRepo),
        Provider<StorageService>.value(value: storage),
      ],
      child: MaterialApp(
        onGenerateRoute: AppRouter.onGenerateRoute,
        home: AdminProductFormView(productId: productId),
      ),
    );
  }

  group('AdminProductFormViewModel Unit Tests', () {
    test('Add mode initializes with no category selected - never a silent '
        'default', () {
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
      );
      expect(vm.isEditMode, isFalse);
      expect(vm.resolvedCategory, isNull);
      expect(vm.categorySelectionBlockedReason, 'Please choose a category.');
      expect(vm.isActive, isTrue);
    });

    test('Edit mode populates from product', () {
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        initialProductId: 'luna-accent-chair',
      );
      expect(vm.isEditMode, isTrue);
      expect(vm.titleController.text, 'Luna Accent Chair');
      expect(vm.publicationStatus, ProductPublicationStatus.published);
      expect(vm.resolvedCategory, isNotNull);
    });

    test('AR Type filtering by category', () {
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
      );
      vm.setCategory(categoryOf('furniture'));
      vm.setExperienceType(ProductExperienceType.roomAr);
      expect(vm.experienceType, ProductExperienceType.roomAr);

      vm.setCategory(categoryOf('clothing'));
      expect(vm.experienceType, ProductExperienceType.none);
    });

    test('selecting VTO keeps model type null until explicitly selected', () {
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
      );
      vm.setCategory(categoryOf('clothing'));
      vm.setExperienceType(ProductExperienceType.virtualTryOn);

      expect(vm.vtoModelType, isNull);

      vm.setVtoModelType(ProductVtoModelType.female);
      expect(vm.vtoModelType, ProductVtoModelType.female);
    });

    ProductArMetadata stagedMeta(String productId, {int version = 1}) =>
        ProductArMetadata(
          storagePath: 'products/$productId/ar/model-v$version.glb',
          modelVersion: '$version',
          sha256: 'a' * 64,
          widthM: 0.7,
          depthM: 0.72,
          heightM: 0.82,
        );

    test('R16: a staged AR contract from AR & Media applies to the form and '
        'stays outside the database', () {
      final beforeCount = db.products.length;
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
      );
      vm.titleController.text = 'Unsaved Chair';
      vm.setExperienceType(ProductExperienceType.roomAr);

      final preview = vm.buildArConfigurationPreview();
      vm.applyArMediaConfiguration(
        preview.copyWith(
          arMetadata: stagedMeta(preview.id),
          arModelAssetPath: '/tmp/picked_model.glb', // pending-upload channel
        ),
      );

      expect(db.products.length, beforeCount);
      expect(vm.titleController.text, 'Unsaved Chair');
      expect(vm.arMetadata, isNotNull);
      expect(vm.pendingArModelFilePath, '/tmp/picked_model.glb');
    });

    test('R16: an existing AR contract preloads and an AR-type change clears '
        'it', () {
      final configured = db
          .getProductById('luna-accent-chair')
          .copyWith(arMetadata: stagedMeta('luna-accent-chair'));
      db.updateProduct(configured);
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        initialProductId: configured.id,
      );

      expect(vm.arMetadata, isNotNull);
      final preview = vm.buildArConfigurationPreview();
      expect(preview.id, configured.id);
      expect(preview.arMetadata, isNotNull);
      vm.setExperienceType(ProductExperienceType.none);
      expect(vm.arMetadata, isNull);
      expect(vm.pendingArModelFilePath, isNull);
    });

    testWidgets('R16: replacing a product\'s AR model via the form deletes the '
        'old Storage object after the write', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('form_replace');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final newGlb = writeBoxGlb(dir: tmp, name: 'chair-v2.glb');

      db.updateProduct(
        db
            .getProductById('luna-accent-chair')
            .copyWith(arMetadata: stagedMeta('luna-accent-chair')),
      );
      final ctx = await _unmountedContext(tester);
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        storageService: storage,
        initialProductId: 'luna-accent-chair',
      );
      addTearDown(vm.dispose);
      vm.applyArMediaConfiguration(
        vm.buildArConfigurationPreview().copyWith(
          arMetadata: stagedMeta('luna-accent-chair', version: 2),
          arModelAssetPath: newGlb.path,
        ),
      );

      expect(await vm.updateProduct(ctx), isTrue);
      expect(
        storage.uploadedArModelPaths,
        contains('products/luna-accent-chair/ar/model-v2.glb'),
      );
      expect(
        storage.deletedArModelPaths,
        contains('products/luna-accent-chair/ar/model-v1.glb'),
      );
    });

    testWidgets('R16: deleting a product also best-effort deletes its AR GLB', (
      tester,
    ) async {
      db.updateProduct(
        db
            .getProductById('luna-accent-chair')
            .copyWith(arMetadata: stagedMeta('luna-accent-chair')),
      );
      final ctx = await _unmountedContext(tester);
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        storageService: storage,
        initialProductId: 'luna-accent-chair',
      );
      addTearDown(vm.dispose);

      await vm.deleteProduct(ctx);
      expect(
        storage.deletedArModelPaths,
        contains('products/luna-accent-chair/ar/model-v1.glb'),
      );
    });

    testWidgets('R16: a replace whose old-GLB cleanup FAILS still commits the '
        'Firestore write and reports an honest warning', (tester) async {
      final tmp = Directory.systemTemp.createTempSync('form_replace_fail');
      addTearDown(() {
        if (tmp.existsSync()) tmp.deleteSync(recursive: true);
      });
      final newGlb = writeBoxGlb(dir: tmp, name: 'chair-v2.glb');
      storage.failDeleteArModel = true;

      db.updateProduct(
        db
            .getProductById('luna-accent-chair')
            .copyWith(arMetadata: stagedMeta('luna-accent-chair')),
      );
      final ctx = await _unmountedContext(tester);
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        storageService: storage,
        initialProductId: 'luna-accent-chair',
      );
      addTearDown(vm.dispose);
      vm.applyArMediaConfiguration(
        vm.buildArConfigurationPreview().copyWith(
          arMetadata: stagedMeta('luna-accent-chair', version: 2),
          arModelAssetPath: newGlb.path,
        ),
      );

      // Firestore write still succeeds (return true) — the contract now points
      // at v2 — but the admin is warned that the old file is still there.
      expect(await vm.updateProduct(ctx), isTrue);
      expect(
        db.getProductById('luna-accent-chair').arMetadata!.modelVersion,
        '2',
      );
      expect(
        storage.uploadedArModelPaths,
        contains('products/luna-accent-chair/ar/model-v2.glb'),
      );
      expect(
        storage.deletedArModelPaths,
        contains('products/luna-accent-chair/ar/model-v1.glb'),
      ); // attempted…
      expect(vm.arModelCleanupWarning, isNotNull); // …but reported as failed
      expect(vm.arModelCleanupWarning, contains('manual cleanup'));
    });

    testWidgets('R16: removing a model via the form when cleanup FAILS clears '
        'the contract and warns', (tester) async {
      storage.failDeleteArModel = true;
      db.updateProduct(
        db
            .getProductById('luna-accent-chair')
            .copyWith(arMetadata: stagedMeta('luna-accent-chair')),
      );
      final ctx = await _unmountedContext(tester);
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        storageService: storage,
        initialProductId: 'luna-accent-chair',
      );
      addTearDown(vm.dispose);
      // AR & Media returned a product with the model removed.
      vm.applyArMediaConfiguration(
        vm.buildArConfigurationPreview().copyWith(clearArMetadata: true),
      );

      expect(await vm.updateProduct(ctx), isTrue);
      expect(db.getProductById('luna-accent-chair').arMetadata, isNull);
      expect(
        storage.deletedArModelPaths,
        contains('products/luna-accent-chair/ar/model-v1.glb'),
      );
      expect(vm.arModelCleanupWarning, isNotNull);
    });

    testWidgets('R16: deleting a product when the GLB cleanup FAILS still '
        'deletes the product and warns', (tester) async {
      storage.failDeleteArModel = true;
      db.updateProduct(
        db
            .getProductById('luna-accent-chair')
            .copyWith(arMetadata: stagedMeta('luna-accent-chair')),
      );
      final ctx = await _unmountedContext(tester);
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        storageService: storage,
        initialProductId: 'luna-accent-chair',
      );
      addTearDown(vm.dispose);

      await vm.deleteProduct(ctx);
      expect(db.products.any((p) => p.id == 'luna-accent-chair'), isFalse);
      expect(
        storage.deletedArModelPaths,
        contains('products/luna-accent-chair/ar/model-v1.glb'),
      );
      expect(vm.arModelCleanupWarning, isNotNull);
    });

    // Phase 9.2 closeout — a committed product image must survive product
    // deletion: a historical `OrderItemModel` snapshot (an already-placed
    // order's line item) can carry that exact same download URL, and there
    // is no way to know from here whether one does. Deleting the Storage
    // object would silently break that order's rendering forever, with no
    // way to detect or undo it — unlike the AR GLB, which no order field
    // ever references. Regression guard: an earlier pass on this same
    // closeout briefly deleted committed images here too (reasoning it
    // would close the same orphaned-object gap the AR-GLB fix closed) and
    // reverted it the same pass once this risk was found — this test exists
    // so that specific mistake can never silently return.
    testWidgets(
      'deleting a product never touches its own committed Storage-hosted '
      'images (protects historical order rendering)',
      (tester) async {
        const mainUrl = 'https://mock-storage.test/products/x/images/1.jpg';
        const galleryUrl = 'https://mock-storage.test/products/x/images/2.jpg';
        db.updateProduct(
          db
              .getProductById('luna-accent-chair')
              .copyWith(
                mainImage: const ProductImageRef(
                  path: mainUrl,
                  source: ProductImageSource.network,
                ),
                galleryMedia: [
                  const ProductImageRef(
                    path: galleryUrl,
                    source: ProductImageSource.network,
                  ),
                ],
              ),
        );
        final ctx = await _unmountedContext(tester);
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
          storageService: storage,
          initialProductId: 'luna-accent-chair',
        );
        addTearDown(vm.dispose);

        await vm.deleteProduct(ctx);

        expect(db.products.any((p) => p.id == 'luna-accent-chair'), isFalse);
        expect(storage.deletedProductImageUrls, isEmpty);
      },
    );

    testWidgets('R16: a successful save with no AR-model change leaves no '
        'cleanup warning', (tester) async {
      db.updateProduct(
        db
            .getProductById('luna-accent-chair')
            .copyWith(arMetadata: stagedMeta('luna-accent-chair')),
      );
      final ctx = await _unmountedContext(tester);
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        storageService: storage,
        initialProductId: 'luna-accent-chair',
      );
      addTearDown(vm.dispose);
      vm.titleController.text = 'Luna Accent Chair (edited)';

      expect(await vm.updateProduct(ctx), isTrue);
      expect(vm.arModelCleanupWarning, isNull);
      expect(storage.deletedArModelPaths, isEmpty);
      // the model contract is preserved untouched
      expect(
        db.getProductById('luna-accent-chair').arMetadata!.storagePath,
        'products/luna-accent-chair/ar/model-v1.glb',
      );
    });

    test('VTO Male/Female choice and garment configuration remain aligned', () {
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
      );
      vm.setCategory(categoryOf('clothing'));
      vm.setExperienceType(ProductExperienceType.virtualTryOn);
      vm.setVtoModelType(ProductVtoModelType.male);
      vm.applyArMediaConfiguration(
        vm.buildArConfigurationPreview().copyWith(
          vtoGarmentAssetPath: 'male_jacket.glb',
        ),
      );

      expect(vm.vtoModelType, ProductVtoModelType.male);
      expect(vm.vtoGarmentAssetPath, 'male_jacket.glb');

      vm.setVtoModelType(ProductVtoModelType.female);
      expect(vm.vtoModelType, ProductVtoModelType.female);
    });

    test('zero active categories blocks Add-mode save with a distinct '
        'message', () {
      final emptyRepo = MockCategoryRepository();
      emptyRepo.debugSetCategories(
        emptyRepo.categories.map((c) => c.copyWith(isActive: false)).toList(),
      );
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: emptyRepo,
      );
      expect(vm.selectableCategories, isEmpty);
      expect(
        vm.categorySelectionBlockedReason,
        'No active categories available - activate or create one first.',
      );
    });

    test('an inactive-but-assigned category stays selected and marked, '
        'never silently swapped', () {
      final repo = MockCategoryRepository();
      final furniture = repo.categories.firstWhere(
        (c) => c.categoryId == 'furniture',
      );
      repo.debugSetCategories([
        for (final c in repo.categories)
          c.categoryId == 'furniture' ? c.copyWith(isActive: false) : c,
      ]);
      final product = db
          .getProductById('luna-accent-chair')
          .copyWith(categoryId: furniture.categoryId);
      db.updateProduct(product);

      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: repo,
        initialProductId: product.id,
      );

      expect(vm.selectedCategoryInactive, isTrue);
      expect(vm.resolvedCategory?.categoryId, 'furniture');
      expect(
        vm.selectableCategories.any((c) => c.categoryId == 'furniture'),
        isTrue,
      );
      // Not blocked - an inactive assignment is a valid past choice, not an
      // error, unlike a missing/deleted category.
      expect(vm.categorySelectionBlockedReason, isNull);
    });

    test('a deleted/missing assigned category blocks save until an admin '
        'explicitly re-picks one', () {
      final product = db
          .getProductById('luna-accent-chair')
          .copyWith(categoryId: 'category-that-no-longer-exists');
      db.updateProduct(product);

      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        initialProductId: product.id,
      );

      expect(vm.selectedCategoryMissing, isTrue);
      expect(
        vm.categorySelectionBlockedReason,
        "This product's category was deleted - please choose a new one.",
      );
    });
  });

  group('AdminProductFormView Widget Tests', () {
    testWidgets('Collapsible arrows functionality', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Check Basic Info is expanded initially
      expect(find.text('Product Name'), findsOneWidget);

      // Tap to collapse
      await tester.tap(find.text('1. Basic Information'));
      await tester.pumpAndSettle();

      // Basic info fields should be hidden
      expect(find.text('Product Name'), findsNothing);

      // Tap again to expand
      await tester.tap(find.text('1. Basic Information'));
      await tester.pumpAndSettle();

      expect(find.text('Product Name'), findsOneWidget);
    });

    testWidgets('Add Mode shows correct buttons', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Save Draft'), findsOneWidget);
      expect(find.text('Publish'), findsOneWidget);
      expect(find.text('Delete'), findsNothing);
      expect(find.text('Update'), findsNothing);
    });

    testWidgets(
      'the category dropdown is sourced from CategoryRepository, not the '
      'fixed enum - "All" is excluded, real category names shown',
      (tester) async {
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();

        await tester.tap(
          find.byType(DropdownButtonFormField<CommerceCategoryModel>),
        );
        await tester.pumpAndSettle();

        expect(find.text('All'), findsNothing);
        expect(find.text('Furniture'), findsWidgets);
        expect(find.text('Clothing'), findsOneWidget);
      },
    );

    testWidgets('a brand-new Admin-created category appears in the dropdown '
        'immediately', (tester) async {
      await categoryRepo.addCategory(
        name: 'Outdoor Furniture',
        kind: ProductCategory.furniture,
      );

      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      await tester.tap(
        find.byType(DropdownButtonFormField<CommerceCategoryModel>),
      );
      await tester.pumpAndSettle();

      expect(find.text('Outdoor Furniture'), findsOneWidget);
    });

    testWidgets('VTO placeholder matches null stored model state', (
      tester,
    ) async {
      final product = db.getProductById('mens-oxford-shirt');
      db.updateProduct(product.copyWith(clearVtoModelType: true));

      await tester.pumpWidget(buildApp(productId: product.id));
      await tester.pumpAndSettle();

      await tester.drag(find.byType(ListView), const Offset(0, -1600));
      await tester.pumpAndSettle();

      expect(find.text('Select Model Type'), findsOneWidget);
      final state = tester.state<FormFieldState<ProductVtoModelType>>(
        find.byType(DropdownButtonFormField<ProductVtoModelType>),
      );
      expect(state.value, isNull);

      await tester.tap(find.byKey(const Key('configure_vto')));
      await tester.pump();
      expect(
        find.text('Select Male or Female before configuration.'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 4));
      await tester.pumpAndSettle();
    });

    testWidgets(
      'R16: Add Product — a staged GLB uploads on publish and the new product '
      'carries a renderable arMetadata contract',
      (tester) async {
        final tmp = Directory.systemTemp.createTempSync('form_ar_test');
        addTearDown(() {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        });
        final glb = writeBoxGlb(dir: tmp, name: 'chair.glb');

        final beforeCount = db.products.length;
        await tester.pumpWidget(buildApp());
        await tester.pumpAndSettle();
        final vm = Provider.of<AdminProductFormViewModel>(
          tester.element(find.text('Product Name')),
          listen: false,
        );
        vm.titleController.text = 'Configured Chair';
        vm.descriptionController.text = 'Configured in the staged AR flow';
        vm.priceController.text = '25000';
        vm.stockController.text = '4';
        vm.setCategory(categoryOf('furniture'));
        vm.setExperienceType(ProductExperienceType.roomAr);

        // Navigate to AR & Media and back (route guard + provider wiring).
        await tester.drag(find.byType(ListView), const Offset(0, -1800));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('configure_room_ar')));
        await tester.pumpAndSettle();
        expect(find.byType(AdminArMediaManagementView), findsOneWidget);
        await tester.tap(find.byKey(const Key('product_scoped_back_button')));
        await tester.pumpAndSettle();
        expect(find.text('Add Product'), findsOneWidget);

        // Simulate the AR & Media screen returning a staged contract with a
        // pending local GLB (the file-pick itself is covered by the
        // AR & Media view/viewmodel tests).
        vm.applyArMediaConfiguration(
          vm.buildArConfigurationPreview().copyWith(
            arMetadata: ProductArMetadata(
              storagePath: 'products/configured-chair/ar/model-v1.glb',
              modelVersion: '1',
              sha256: 'b' * 64,
              widthM: 0.7,
              depthM: 0.72,
              heightM: 0.82,
            ),
            arModelAssetPath: glb.path,
          ),
        );

        vm.addImages([
          const ProductImageRef(
            path: 'assets/images/branding/twin_ar_logo_mark.png',
          ),
        ], tester.element(find.text('Add Product')));
        expect(
          await vm.publish(tester.element(find.text('Add Product'))),
          isTrue,
        );

        expect(db.products.length, beforeCount + 1);
        expect(
          storage.uploadedArModelPaths,
          contains('products/configured-chair/ar/model-v1.glb'),
        );
        final saved = db.getProductById('configured-chair');
        expect(saved.experienceType, ProductExperienceType.roomAr);
        expect(saved.arMetadata, isNotNull);
        expect(
          saved.arMetadata!.storagePath,
          'products/configured-chair/ar/model-v1.glb',
        );
        expect(saved.hasRenderableArModel, isTrue);
        expect(saved.arModelAssetPath, isNull); // legacy field not written
        await tester.pump(const Duration(seconds: 4));
        await tester.pumpAndSettle();
      },
    );

    testWidgets(
      'R16: Add Product — a Firestore write failure rolls the uploaded GLB '
      'back',
      (tester) async {
        final tmp = Directory.systemTemp.createTempSync('form_ar_rollback');
        addTearDown(() {
          if (tmp.existsSync()) tmp.deleteSync(recursive: true);
        });
        final glb = writeBoxGlb(dir: tmp, name: 'chair.glb');

        // A context that is deliberately unmounted by the time `publish`
        // finishes, so `_persist`'s `if (context.mounted)` skips the toast —
        // this test asserts the rollback contract, not UI feedback (that is
        // covered elsewhere), and AppToast keeps fragile global state.
        await tester.pumpWidget(
          const MaterialApp(home: Scaffold(body: Text('ctx-host'))),
        );
        final ctx = tester.element(find.text('ctx-host'));
        await tester.pumpWidget(const MaterialApp(home: SizedBox()));

        final vm = AdminProductFormViewModel(
          database: _AddProductThrows(),
          categoryRepository: categoryRepo,
          storageService: storage,
        );
        addTearDown(vm.dispose);
        vm.titleController.text = 'Doomed Chair';
        vm.descriptionController.text = 'x';
        vm.priceController.text = '1000';
        vm.stockController.text = '1';
        vm.setCategory(categoryOf('furniture'));
        vm.setExperienceType(ProductExperienceType.roomAr);
        vm.applyArMediaConfiguration(
          vm.buildArConfigurationPreview().copyWith(
            arMetadata: ProductArMetadata(
              storagePath: 'products/doomed-chair/ar/model-v1.glb',
              modelVersion: '1',
              sha256: 'c' * 64,
              widthM: 0.7,
              depthM: 0.72,
              heightM: 0.82,
            ),
            arModelAssetPath: glb.path,
          ),
        );
        vm.addImages([
          const ProductImageRef(
            path: 'assets/images/branding/twin_ar_logo_mark.png',
          ),
        ], ctx);

        final ok = await vm.publish(ctx);
        expect(ok, isFalse);
        expect(storage.uploadedArModelPaths, hasLength(1));
        expect(
          storage.deletedArModelPaths,
          contains(storage.uploadedArModelPaths.first),
        );
      },
    );

    testWidgets('Edit Mode shows correct buttons', (tester) async {
      await tester.pumpWidget(buildApp(productId: 'luna-accent-chair'));
      await tester.pumpAndSettle();

      expect(find.text('Save Draft'), findsNothing);
      expect(find.text('Publish'), findsNothing);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Update'), findsOneWidget);
    });

    testWidgets('Dirty form PopScope triggers Discard dialog', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      // Try to pop before dirty -> pops directly (though maybePop returns true if it popped)

      // Enter some text
      await tester.enterText(find.byType(TextField).first, 'Test Product');
      await tester.pumpAndSettle();

      // Try to pop
      final dynamic state = tester.state(find.byType(Navigator));
      state.maybePop();
      await tester.pumpAndSettle();

      expect(find.text('Discard Changes?'), findsOneWidget);

      // Tap Keep Editing
      await tester.tap(find.text('Keep Editing'));
      await tester.pumpAndSettle();

      expect(find.text('Discard Changes?'), findsNothing);
    });

    testWidgets('Draft Edit Mode shows correct buttons', (tester) async {
      final draftId = 'draft-product-id';
      db.addProduct(
        ProductModel(
          id: draftId,
          sku: 'DRAFT-123',
          title: 'Draft Product',
          description: 'A draft',
          priceAmount: 100,
          originalPriceAmount: 100,
          categoryId: 'furniture',
          categoryKind: ProductCategory.furniture,
          subcategory: 'Chairs',
          stockQuantity: 10,
          publicationStatus: ProductPublicationStatus.draft,
          addedDate: DateTime.now(),
          isActive: true,
          showInCatalog: true,
          experienceType: ProductExperienceType.none,
          availableColors: {},
          availableSizes: {},
          specifications: [],
          mainImage: const ProductImageRef(path: 'assets/images/logo_mark.png'),
          deliveryEstimate: '3-5 Days',
        ),
      );

      await tester.pumpWidget(buildApp(productId: draftId));
      await tester.pumpAndSettle();

      expect(find.text('Save Draft'), findsOneWidget);
      expect(find.text('Publish'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
      expect(find.text('Update'), findsNothing);
    });
  });
}

class _AddProductThrows extends MockCommerceDatabase {
  @override
  Future<void> addProduct(ProductModel product) =>
      Future.error(StateError('boom'));
}

/// A `BuildContext` that is deliberately unmounted by the time it's used, so
/// the ViewModel's `if (context.mounted)` guards skip every `AppToast` call
/// (AppToast keeps fragile global state that cross-contaminates tests).
Future<BuildContext> _unmountedContext(WidgetTester tester) async {
  await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Text('ctx'))));
  final ctx = tester.element(find.text('ctx'));
  await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  return ctx;
}
