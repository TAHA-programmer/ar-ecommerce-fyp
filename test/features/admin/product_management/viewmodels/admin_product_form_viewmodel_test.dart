import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/features/admin/product_management/viewmodels/admin_product_form_viewmodel.dart';

/// Real seed data/reads, but every product write throws - used to verify
/// the Phase 8.6 error-handling paths this file focuses on, without a real
/// (or fake) Firestore backend.
class _ThrowingWritesDatabase extends MockCommerceDatabase {
  @override
  Future<void> addProduct(ProductModel product) =>
      Future.error(StateError('boom'));
  @override
  Future<void> updateProduct(ProductModel product) =>
      Future.error(StateError('boom'));
  @override
  Future<void> deleteProduct(String productId) =>
      Future.error(StateError('boom'));
}

void main() {
  group('AdminProductFormViewModel - write error handling (Phase 8.6)', () {
    late BuildContext capturedContext;

    Future<void> pumpContext(WidgetTester tester) {
      return tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              capturedContext = context;
              return const SizedBox();
            },
          ),
        ),
      );
    }

    testWidgets(
      'saveDraft (add mode) catches an addProduct failure, surfaces false, '
      'and does not propagate the exception',
      (tester) async {
        await pumpContext(tester);
        final db = _ThrowingWritesDatabase();
        final categoryRepo = MockCategoryRepository();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: categoryRepo,
        );
        vm.titleController.text = 'Test Product';
        vm.priceController.text = '1000';
        vm.stockController.text = '5';
        vm.setCategory(categoryRepo.categories.first);
        vm.addImages(const [
          ProductImageRef(path: 'assets/x.png'),
        ], capturedContext);

        final result = await vm.saveDraft(capturedContext);

        expect(result, isFalse);
        expect(vm.isLoading, isFalse);

        // Let the AppToast.error's internal auto-dismiss timer finish
        // before the test tears down its widget tree.
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 350));
      },
    );

    testWidgets(
      'updateProduct (edit mode) catches an updateProduct failure and '
      'surfaces false',
      (tester) async {
        await pumpContext(tester);
        final db = _ThrowingWritesDatabase();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: MockCategoryRepository(),
          initialProductId: 'luna-accent-chair',
        );
        vm.descriptionController.text = 'Still a valid description.';

        final result = await vm.updateProduct(capturedContext);

        expect(result, isFalse);
        expect(vm.isLoading, isFalse);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 350));
      },
    );

    testWidgets(
      'deleteProduct (edit mode) catches a deleteProduct failure without '
      'throwing',
      (tester) async {
        await pumpContext(tester);
        final db = _ThrowingWritesDatabase();
        final vm = AdminProductFormViewModel(
          database: db,
          categoryRepository: MockCategoryRepository(),
          initialProductId: 'luna-accent-chair',
        );

        await expectLater(vm.deleteProduct(capturedContext), completes);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pump(const Duration(seconds: 3));
        await tester.pump(const Duration(milliseconds: 350));
      },
    );
  });
}
