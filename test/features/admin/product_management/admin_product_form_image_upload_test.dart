import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/admin/product_management/viewmodels/admin_product_form_viewmodel.dart';
import '../../../support/test_image_files.dart';

/// Wraps [MockCommerceDatabase] and makes `addProduct`/`updateProduct` throw
/// - used to exercise `AdminProductFormViewModel`'s image-upload rollback
/// path (Storage upload succeeds, the following Firestore write fails).
class _ThrowingWriteCommerceDatabase extends MockCommerceDatabase {
  bool failWrites = false;

  @override
  Future<void> addProduct(ProductModel product) async {
    if (failWrites) throw StateError('simulated Firestore failure');
    return super.addProduct(product);
  }

  @override
  Future<void> updateProduct(ProductModel product) async {
    if (failWrites) throw StateError('simulated Firestore failure');
    return super.updateProduct(product);
  }
}

void main() {
  tearDown(() async {
    await TestImageFile.cleanUp();
  });

  /// Every test needs a real BuildContext to call context-requiring
  /// ViewModel methods (`addImages`, `saveDraft`, etc.) - mirrors the
  /// pattern already used elsewhere in this suite for context-taking
  /// Admin ViewModel methods (e.g. `AdminProductManagementViewModel
  /// .deleteProduct`).
  Future<BuildContext> pumpContext(WidgetTester tester) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );
    return ctx;
  }

  /// Every save method shows an `AppToast` (a timed overlay) on completion -
  /// flush its 3-second auto-dismiss timer so it doesn't trip
  /// flutter_test's "no dangling timers" check at teardown, matching the
  /// existing pattern in `admin_product_form_test.dart`.
  Future<void> flushToast(WidgetTester tester) async {
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pumpAndSettle();
  }

  /// Creates a staged `.file` [ProductImageRef] backed by a REAL temporary
  /// file - `AdminProductFormViewModel`'s upload path now preflights every
  /// staged file (existence, type, size) before uploading anything, so a
  /// fabricated non-existent path (used before preflight validation
  /// existed) would fail every one of these tests at the wrong step.
  /// [TestImageFile.create] is sync-backed internally specifically so it -
  /// and `validateImageFileForUpload`'s own checks - are safe to call
  /// directly inside a `testWidgets` body with no special wrapping; see
  /// both of their doc comments for why that matters here.
  Future<ProductImageRef> fileRef(
    WidgetTester tester, {
    String extension = 'jpg',
    int sizeBytes = 1024,
  }) async {
    final file = await TestImageFile.create(
      extension: extension,
      sizeBytes: sizeBytes,
    );
    return ProductImageRef(path: file.path, source: ProductImageSource.file);
  }

  group('AdminProductFormViewModel image upload lifecycle', () {
    testWidgets(
      'saveDraft uploads staged .file images and converts them to .network',
      (tester) async {
        final context = await pumpContext(tester);
        final db = MockCommerceDatabase();
        final storage = MockStorageService();
        final categoryRepo = MockCategoryRepository();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
          storageService: storage,
        );

        vm.titleController.text = 'New Sofa';
        vm.priceController.text = '1000';
        vm.stockController.text = '5';
        vm.setCategory(categoryRepo.categories.first);
        vm.addImages([await fileRef(tester), await fileRef(tester)], context);

        final ok = await vm.saveDraft(context);
        await flushToast(tester);

        expect(ok, isTrue);
        expect(storage.uploadedProductImageUrls, hasLength(2));
        expect(
          vm.images.every((r) => r.source == ProductImageSource.network),
          isTrue,
        );
        expect(vm.primaryImage!.source, ProductImageSource.network);
      },
    );

    testWidgets(
      'primary image selection is preserved through upload, even when not first',
      (tester) async {
        final context = await pumpContext(tester);
        final db = MockCommerceDatabase();
        final storage = MockStorageService();
        final categoryRepo = MockCategoryRepository();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
          storageService: storage,
        );

        vm.titleController.text = 'New Chair';
        vm.priceController.text = '500';
        vm.stockController.text = '3';
        vm.setCategory(categoryRepo.categories.first);
        final second = await fileRef(tester);
        vm.addImages([await fileRef(tester), second], context);
        vm.setPrimaryImage(second);

        final ok = await vm.saveDraft(context);
        await flushToast(tester);

        expect(ok, isTrue);
        // The uploaded URL for the second staged image must have become
        // the primary - not silently falling back to the first.
        expect(vm.primaryImage!.path, storage.uploadedProductImageUrls[1]);
      },
    );

    testWidgets(
      'saving again without leaving the screen never re-uploads already-network images',
      (tester) async {
        final context = await pumpContext(tester);
        final db = MockCommerceDatabase();
        final storage = MockStorageService();
        final categoryRepo = MockCategoryRepository();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
          storageService: storage,
        );

        vm.titleController.text = 'Draft Then Publish';
        vm.priceController.text = '750';
        vm.stockController.text = '2';
        vm.setCategory(categoryRepo.categories.first);
        vm.descriptionController.text = 'A description';
        vm.addImages([await fileRef(tester)], context);

        expect(await vm.saveDraft(context), isTrue);
        await flushToast(tester);
        expect(storage.uploadCallCount, 1);

        // Re-save (Draft -> Publish) without leaving the screen. The staged
        // image is already `.network` from the first save, so this must not
        // upload it a second time.
        expect(await vm.publish(context), isTrue);
        await flushToast(tester);
        expect(storage.uploadCallCount, 1);
      },
    );

    testWidgets('a save with no staged device images never touches storage', (
      tester,
    ) async {
      final context = await pumpContext(tester);
      final db = MockCommerceDatabase();
      final storage = MockStorageService();
      final categoryRepo = MockCategoryRepository();
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        storageService: storage,
        initialProductId: 'luna-accent-chair',
      );

      // Edit an existing (asset-image) product without touching images.
      final ok = await vm.updateProduct(context);
      await flushToast(tester);

      expect(ok, isTrue);
      expect(storage.uploadCallCount, 0);
    });

    testWidgets(
      'a Firestore write failure rolls back only the newly uploaded images and leaves staged state untouched',
      (tester) async {
        final context = await pumpContext(tester);
        final db = _ThrowingWriteCommerceDatabase();
        final storage = MockStorageService();
        final categoryRepo = MockCategoryRepository();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
          storageService: storage,
        );

        vm.titleController.text = 'Will Fail';
        vm.priceController.text = '100';
        vm.stockController.text = '1';
        vm.setCategory(categoryRepo.categories.first);
        vm.addImages([await fileRef(tester), await fileRef(tester)], context);

        db.failWrites = true;
        final ok = await vm.saveDraft(context);
        await flushToast(tester);

        expect(ok, isFalse);
        expect(storage.uploadedProductImageUrls, hasLength(2));
        // Every uploaded-this-save object must be rolled back - and only
        // those objects.
        expect(
          storage.deletedProductImageUrls,
          storage.uploadedProductImageUrls,
        );
        // The ViewModel's own staged images must NOT have been flipped to
        // the now-deleted `.network` URLs - they must still be the
        // original `.file` refs, so the form doesn't render broken images
        // after a failed save.
        expect(
          vm.images.every((r) => r.source == ProductImageSource.file),
          isTrue,
        );

        // Retrying after the transient failure clears must work normally
        // and upload fresh objects (not reuse the rolled-back URLs).
        db.failWrites = false;
        final retryOk = await vm.saveDraft(context);
        await flushToast(tester);
        expect(retryOk, isTrue);
        expect(storage.uploadedProductImageUrls, hasLength(4));
      },
    );

    testWidgets(
      'a partial-batch Storage upload failure (image 1 succeeds, image 2 fails) rolls back only image 1 and leaves staged local refs intact',
      (tester) async {
        final context = await pumpContext(tester);
        final db = MockCommerceDatabase();
        final storage = MockStorageService()
          ..failProductImageUploadOnCallNumber = 2;
        final categoryRepo = MockCategoryRepository();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
          storageService: storage,
        );

        vm.titleController.text = 'Partial Batch';
        vm.priceController.text = '300';
        vm.stockController.text = '2';
        vm.setCategory(categoryRepo.categories.first);
        final first = await fileRef(tester);
        final second = await fileRef(tester);
        vm.addImages([first, second], context);

        final ok = await vm.saveDraft(context);
        await flushToast(tester);

        expect(ok, isFalse);
        // Only the first image's upload ever succeeded before the second
        // one failed - the batch stops there, it does not continue
        // uploading further images after a failure.
        expect(storage.uploadedProductImageUrls, hasLength(1));
        // That one successful upload must be rolled back (deleted), since
        // the overall save did not go through.
        expect(
          storage.deletedProductImageUrls,
          storage.uploadedProductImageUrls,
        );
        // Nothing in this database's product write was ever reached - the
        // failure happened during the upload phase, before addProduct was
        // even called. Staged local state must be completely untouched:
        // still exactly the two original `.file` refs, in order.
        expect(vm.images, hasLength(2));
        expect(vm.images[0].source, ProductImageSource.file);
        expect(vm.images[0].path, first.path);
        expect(vm.images[1].source, ProductImageSource.file);
        expect(vm.images[1].path, second.path);
      },
    );

    testWidgets(
      'never deletes a previously committed (.network) image, even when removed from the staged gallery',
      (tester) async {
        final context = await pumpContext(tester);
        final db = MockCommerceDatabase();
        final storage = MockStorageService();
        final categoryRepo = MockCategoryRepository();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
          storageService: storage,
        );

        vm.titleController.text = 'Two Images';
        vm.priceController.text = '200';
        vm.stockController.text = '4';
        vm.setCategory(categoryRepo.categories.first);
        final first = await fileRef(tester);
        final second = await fileRef(tester);
        vm.addImages([first, second], context);
        expect(await vm.saveDraft(context), isTrue);
        await flushToast(tester);
        final committedUrl = vm.images.first.path;

        // Remove the now-committed first image from the staged gallery and
        // save again - the underlying Storage object must never be deleted
        // (a historical OrderItemModel snapshot may still reference it).
        vm.removeImage(vm.images.first);
        expect(await vm.saveDraft(context), isTrue);
        await flushToast(tester);

        expect(storage.deletedProductImageUrls, isEmpty);
        expect(storage.uploadedProductImageUrls, contains(committedUrl));
      },
    );
  });

  group('AdminProductFormViewModel image upload preflight validation', () {
    testWidgets(
      'rejects an oversized staged image and uploads nothing at all - the whole batch is preflighted before the first upload',
      (tester) async {
        final context = await pumpContext(tester);
        final db = MockCommerceDatabase();
        final storage = MockStorageService();
        final categoryRepo = MockCategoryRepository();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
          storageService: storage,
        );

        vm.titleController.text = 'Oversized Batch';
        vm.priceController.text = '400';
        vm.stockController.text = '1';
        vm.setCategory(categoryRepo.categories.first);
        final good = await fileRef(tester);
        final oversized = await fileRef(tester, sizeBytes: 11 * 1024 * 1024);
        // The oversized file is staged SECOND - proves the whole batch is
        // validated up front, not lazily discovered mid-upload after the
        // first (valid) file has already gone to Storage.
        vm.addImages([good, oversized], context);

        final ok = await vm.saveDraft(context);
        await flushToast(tester);

        expect(ok, isFalse);
        expect(storage.uploadedProductImageUrls, isEmpty);
        expect(storage.uploadCallCount, 0);
        expect(
          vm.images.every((r) => r.source == ProductImageSource.file),
          isTrue,
        );
      },
    );

    testWidgets('rejects an unsupported staged file type and uploads nothing', (
      tester,
    ) async {
      final context = await pumpContext(tester);
      final db = MockCommerceDatabase();
      final storage = MockStorageService();
      final categoryRepo = MockCategoryRepository();
      final vm = AdminProductFormViewModel(
        database: db,
        categoryRepository: categoryRepo,
        storageService: storage,
      );

      vm.titleController.text = 'Bad Type Batch';
      vm.priceController.text = '400';
      vm.stockController.text = '1';
      vm.setCategory(categoryRepo.categories.first);
      vm.addImages([await fileRef(tester, extension: 'gif')], context);

      final ok = await vm.saveDraft(context);
      await flushToast(tester);

      expect(ok, isFalse);
      expect(storage.uploadedProductImageUrls, isEmpty);
    });
  });
}
