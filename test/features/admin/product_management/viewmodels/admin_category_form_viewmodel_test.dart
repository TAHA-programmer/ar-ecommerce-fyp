import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/features/admin/product_management/viewmodels/admin_category_form_viewmodel.dart';

Future<BuildContext> _pumpContext(WidgetTester tester) async {
  late BuildContext captured;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          captured = context;
          return const SizedBox();
        },
      ),
    ),
  );
  return captured;
}

Future<void> _settleToast(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(seconds: 3));
  await tester.pump(const Duration(milliseconds: 350));
}

/// Deliberately uses the SYNCHRONOUS dart:io APIs - see
/// `image_upload_validator.dart`'s own doc comment for why the async
/// variants hang inside a `testWidgets` body.
File _tempImageFile() {
  final dir = Directory.systemTemp.createTempSync('twinar-category-test-');
  final file = File('${dir.path}/category.png');
  file.writeAsBytesSync(List.filled(128, 1));
  return file;
}

void main() {
  late MockCategoryRepository mockCategoryRepository;
  late MockStorageService mockStorageService;

  setUp(() {
    mockCategoryRepository = MockCategoryRepository();
    mockStorageService = MockStorageService();
  });

  group('AdminCategoryFormViewModel - Add mode', () {
    testWidgets('rejects creating a category with no image, without '
        'touching Storage/Firestore', (tester) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = 'Outdoor Furniture';
      viewModel.setKind(ProductCategory.furniture);

      final result = await viewModel.save(context);

      expect(result, isFalse);
      expect(
        mockCategoryRepository.categories.any(
          (c) => c.categoryId == 'outdoor-furniture',
        ),
        isFalse,
      );
      expect(mockStorageService.uploadedCategoryImageUrls, isEmpty);
      await _settleToast(tester);
    });

    testWidgets('uploads the image before creating the document', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = 'Lamps';
      viewModel.setKind(ProductCategory.lighting);
      viewModel.setImageFile(_tempImageFile());

      final result = await viewModel.save(context);

      expect(result, isTrue);
      expect(mockStorageService.uploadedCategoryImageUrls.length, 1);
      final created = mockCategoryRepository.categories.firstWhere(
        (c) => c.categoryId == 'lamps',
      );
      expect(
        created.imageUrl,
        mockStorageService.uploadedCategoryImageUrls.single,
      );
      await _settleToast(tester);
    });

    testWidgets('rolls back the uploaded image if the Firestore create fails', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      mockCategoryRepository.failAddCategoryWith = StateError(
        'simulated create failure',
      );
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = 'Lamps';
      viewModel.setKind(ProductCategory.lighting);
      viewModel.setImageFile(_tempImageFile());

      final result = await viewModel.save(context);

      expect(result, isFalse);
      expect(mockStorageService.uploadedCategoryImageUrls.length, 1);
      expect(mockStorageService.deletedCategoryImageUrls.length, 1);
      expect(
        mockStorageService.deletedCategoryImageUrls.single,
        mockStorageService.uploadedCategoryImageUrls.single,
      );
      await _settleToast(tester);
    });

    testWidgets('rejects a case-insensitive duplicate display name', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = '  FURNITURE  ';
      viewModel.setKind(ProductCategory.furniture);

      final result = await viewModel.save(context);

      expect(result, isFalse);
      expect(mockCategoryRepository.categories.length, 5); // unchanged
      await _settleToast(tester);
    });

    testWidgets('rejects an empty name without touching Storage/Firestore', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = '   ';

      final result = await viewModel.save(context);

      expect(result, isFalse);
      expect(mockStorageService.uploadedCategoryImageUrls, isEmpty);
      await _settleToast(tester);
    });

    testWidgets('rejects a name that slugifies to empty ("!!!") BEFORE any '
        'image upload or Firestore write, even when an image is provided', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = '!!!';
      viewModel.setImageFile(_tempImageFile());

      final result = await viewModel.save(context);

      expect(result, isFalse);
      expect(mockStorageService.uploadedCategoryImageUrls, isEmpty);
      expect(mockCategoryRepository.categories.length, 5); // unchanged
      await _settleToast(tester);
    });

    testWidgets('rejects ProductCategory.all BEFORE any image upload or '
        'Firestore write, even when an image is provided', (tester) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = 'Everything';
      viewModel.setKind(ProductCategory.all);
      viewModel.setImageFile(_tempImageFile());

      final result = await viewModel.save(context);

      expect(result, isFalse);
      expect(mockStorageService.uploadedCategoryImageUrls, isEmpty);
      expect(mockCategoryRepository.categories.length, 5); // unchanged
      await _settleToast(tester);
    });

    testWidgets('a second concurrent submit is ignored while the first is '
        'still in flight (duplicate-submit prevention)', (tester) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = 'Lamps';
      viewModel.setKind(ProductCategory.lighting);
      viewModel.setImageFile(_tempImageFile());

      final first = viewModel.save(context);
      expect(viewModel.isSaving, isTrue);

      viewModel.nameController.text = 'Other Lamps';
      final second = await viewModel.save(context);
      expect(second, isFalse); // dropped - a save was already in flight

      final firstResult = await first;
      expect(firstResult, isTrue);
      expect(
        mockCategoryRepository.categories.any(
          (c) => c.categoryId == 'other-lamps',
        ),
        isFalse,
      );
      await _settleToast(tester);
    });
  });

  group('AdminCategoryFormViewModel - Edit mode', () {
    testWidgets('a nonexistent categoryId surfaces a clean error state, '
        'not a crash', (tester) async {
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: 'does-not-exist',
      );
      addTearDown(viewModel.dispose);

      expect(viewModel.error, isNotNull);
    });

    testWidgets('pre-fills name/kind/active/image from the loaded category', (
      tester,
    ) async {
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: 'furniture',
      );
      addTearDown(viewModel.dispose);

      expect(viewModel.error, isNull);
      expect(viewModel.nameController.text, 'Furniture');
      expect(viewModel.kind, ProductCategory.furniture);
      expect(viewModel.isActive, isTrue);
      expect(viewModel.hasUnsavedChanges, isFalse);
    });

    testWidgets('setKind is a no-op in edit mode - kind is permanently '
        'immutable', (tester) async {
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: 'furniture',
      );
      addTearDown(viewModel.dispose);

      viewModel.setKind(ProductCategory.decor);

      expect(viewModel.kind, ProductCategory.furniture); // unchanged
    });

    testWidgets('renames a category, key/kind stay the same', (tester) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: 'furniture',
      );
      addTearDown(viewModel.dispose);
      viewModel.nameController.text = 'Home Furniture';
      // The seeded mock category has no image by default (imageUrl: '') -
      // an image is now compulsory on every save, so this test - which is
      // about the rename/key/kind behavior, not images - supplies one.
      viewModel.setImageFile(_tempImageFile());

      final result = await viewModel.save(context);

      expect(result, isTrue);
      final updated = mockCategoryRepository.categories.firstWhere(
        (c) => c.categoryId == 'furniture',
      );
      expect(updated.name, 'Home Furniture');
      expect(updated.key, 'furniture');
      expect(updated.kind, ProductCategory.furniture);
      await _settleToast(tester);
    });

    testWidgets('replacing the image deletes the previous one only after '
        'the Firestore write succeeds', (tester) async {
      final context = await _pumpContext(tester);
      final withImage = await mockCategoryRepository.addCategory(
        name: 'Lamps',
        kind: ProductCategory.lighting,
        imageUrl: 'https://old.example/lamp.png',
      );
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: withImage.categoryId,
      );
      addTearDown(viewModel.dispose);
      viewModel.setImageFile(_tempImageFile());

      final result = await viewModel.save(context);

      expect(result, isTrue);
      expect(mockStorageService.uploadedCategoryImageUrls.length, 1);
      expect(mockStorageService.deletedCategoryImageUrls, [
        'https://old.example/lamp.png',
      ]);
      await _settleToast(tester);
    });

    testWidgets('rolls back the newly uploaded replacement image if the '
        'Firestore update fails', (tester) async {
      final context = await _pumpContext(tester);
      final withImage = await mockCategoryRepository.addCategory(
        name: 'Lamps',
        kind: ProductCategory.lighting,
        imageUrl: 'https://old.example/lamp.png',
      );
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: withImage.categoryId,
      );
      addTearDown(viewModel.dispose);
      mockCategoryRepository.failUpdateCategoryWith = StateError('boom');
      viewModel.setImageFile(_tempImageFile());

      final result = await viewModel.save(context);

      expect(result, isFalse);
      expect(mockStorageService.uploadedCategoryImageUrls.length, 1);
      expect(mockStorageService.deletedCategoryImageUrls.length, 1);
      expect(
        mockStorageService.deletedCategoryImageUrls.single,
        mockStorageService.uploadedCategoryImageUrls.single,
      );
      expect(
        mockStorageService.deletedCategoryImageUrls.contains(
          'https://old.example/lamp.png',
        ),
        isFalse,
      );
      await _settleToast(tester);
    });

    testWidgets('rejects a case-insensitive duplicate name against another '
        'category, but allows saving with its own unchanged name', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: 'decor',
      );
      addTearDown(viewModel.dispose);
      final originalName = viewModel.nameController.text;

      viewModel.nameController.text = 'clothing';
      final clash = await viewModel.save(context);
      expect(clash, isFalse);

      viewModel.nameController.text = originalName;
      viewModel.setActive(false);
      // The seeded mock category has no image by default - compulsory now.
      viewModel.setImageFile(_tempImageFile());
      final noOp = await viewModel.save(context);
      expect(noOp, isTrue);
      await _settleToast(tester);
    });

    testWidgets('clearImage without replacing it blocks save - an image is '
        'compulsory, clearing does not leave a category image-less', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final withImage = await mockCategoryRepository.addCategory(
        name: 'Lamps',
        kind: ProductCategory.lighting,
        imageUrl: 'https://old.example/lamp.png',
      );
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: withImage.categoryId,
      );
      addTearDown(viewModel.dispose);
      viewModel.clearImage();
      expect(viewModel.hasImage, isFalse);

      final result = await viewModel.save(context);

      expect(result, isFalse);
      final unchanged = mockCategoryRepository.categories.firstWhere(
        (c) => c.categoryId == withImage.categoryId,
      );
      expect(unchanged.imageUrl, 'https://old.example/lamp.png');
      expect(mockStorageService.deletedCategoryImageUrls, isEmpty);
      await _settleToast(tester);
    });

    testWidgets('clearImage followed by picking a new image allows save', (
      tester,
    ) async {
      final context = await _pumpContext(tester);
      final withImage = await mockCategoryRepository.addCategory(
        name: 'Lamps',
        kind: ProductCategory.lighting,
        imageUrl: 'https://old.example/lamp.png',
      );
      final viewModel = AdminCategoryFormViewModel(
        categoryRepository: mockCategoryRepository,
        storageService: mockStorageService,
        initialCategoryId: withImage.categoryId,
      );
      addTearDown(viewModel.dispose);
      viewModel.clearImage();
      viewModel.setImageFile(_tempImageFile());

      final result = await viewModel.save(context);

      expect(result, isTrue);
      final updated = mockCategoryRepository.categories.firstWhere(
        (c) => c.categoryId == withImage.categoryId,
      );
      expect(updated.imageUrl, isNotEmpty);
      expect(updated.imageUrl, isNot('https://old.example/lamp.png'));
      await _settleToast(tester);
    });
  });
}
