import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/utils/stock_status.dart';
import 'package:twin_ar/features/admin/dashboard/viewmodels/admin_dashboard_viewmodel.dart';
import 'package:twin_ar/features/admin/inventory/viewmodels/admin_inventory_viewmodel.dart';

/// Simulates a backend where an inventory `updateStock` commits the quantity
/// immediately but the server-resolved `lastStockUpdatedAt` only arrives on
/// a later snapshot - the exact timing `FirestoreCommerceDatabase` sees and
/// the reason [AdminInventoryViewModel] needs an optimistic-then-converge
/// timestamp (Phase 8.11).
class _DeferredStampDb extends MockCommerceDatabase {
  @override
  Future<void> updateStock(String productId, int newStockQuantity) {
    // Commit the quantity now, defer the stamp - the exact window the real
    // Firestore path has while `serverTimestamp()` is still unresolved.
    return debugUpdateStockQuantityOnly(productId, newStockQuantity);
  }

  /// A later snapshot resolves the server timestamp.
  void resolveServerStamp(String productId) {
    super.updateStock(productId, getProductById(productId).stockQuantity);
  }

  /// An unrelated snapshot notification, to prove the converged value sticks.
  void notifyDummy() => notifyListeners();
}

void main() {
  late MockCommerceDatabase db;
  late MockCategoryRepository categoryRepo;
  late AdminInventoryViewModel viewModel;

  setUp(() {
    db = MockCommerceDatabase();
    categoryRepo = MockCategoryRepository();
    viewModel = AdminInventoryViewModel(db, categoryRepo);
  });

  tearDown(() {
    viewModel.dispose();
  });

  group('AdminInventoryViewModel - listing & filters', () {
    test('initial state exposes every shared product with no filters', () {
      expect(viewModel.filteredProducts.length, db.products.length);
      expect(viewModel.searchQuery, '');
      expect(viewModel.selectedCategory, ProductCategory.all);
      expect(viewModel.lowStockOnly, isFalse);
      expect(viewModel.lowStockThreshold, CommerceDatabase.lowStockThreshold);
    });

    test('search matches by product title', () {
      viewModel.setSearchQuery('Luna Accent Chair');
      final results = viewModel.filteredProducts;
      expect(results, hasLength(1));
      expect(results.first.id, 'luna-accent-chair');
    });

    test('search matches by SKU, case-insensitively and trimmed', () {
      final product = db.getProductById('luna-accent-chair');
      viewModel.setSearchQuery('  ${product.sku.toLowerCase()}  ');
      final results = viewModel.filteredProducts;
      expect(results.any((p) => p.id == product.id), isTrue);
    });

    test('search matches by broad kind label', () {
      viewModel.setSearchQuery('clothing');
      final results = viewModel.filteredProducts;
      expect(results, isNotEmpty);
      expect(
        results.every((p) => p.categoryKind == ProductCategory.clothing),
        isTrue,
      );
    });

    test('search matches by the product\'s real assigned category name '
        '(Phase 8.8b), not just its broad kind label', () async {
      final custom = await categoryRepo.addCategory(
        name: 'Outdoor Furniture',
        kind: ProductCategory.furniture,
      );
      final product = db.getProductById('luna-accent-chair');
      await db.updateProduct(
        product.copyWith(
          categoryId: custom.categoryId,
          categoryKind: custom.kind,
        ),
      );

      viewModel.setSearchQuery('Outdoor');
      final results = viewModel.filteredProducts;

      expect(results.any((p) => p.id == product.id), isTrue);
    });

    test('category filter narrows to the selected category only', () {
      viewModel.setCategory(ProductCategory.furniture);
      final results = viewModel.filteredProducts;
      expect(results, isNotEmpty);
      expect(
        results.every((p) => p.categoryKind == ProductCategory.furniture),
        isTrue,
      );
    });

    test('ProductCategory.all resets the category filter', () {
      viewModel.setCategory(ProductCategory.furniture);
      viewModel.setCategory(ProductCategory.all);
      expect(viewModel.filteredProducts.length, db.products.length);
    });

    test(
      'Low Stock Only shows exactly the low-stock bucket, not out-of-stock',
      () {
        final target = db.products.first;
        final outOfStockTarget = db.products[1];
        db.updateStock(target.id, CommerceDatabase.lowStockThreshold);
        db.updateStock(outOfStockTarget.id, 0);

        viewModel.setLowStockOnly(true);
        final results = viewModel.filteredProducts;

        expect(results.any((p) => p.id == target.id), isTrue);
        expect(results.any((p) => p.id == outOfStockTarget.id), isFalse);
        expect(
          results.every(
            (p) =>
                stockStatusForQuantity(
                  p.stockQuantity,
                  CommerceDatabase.lowStockThreshold,
                ) ==
                StockStatus.lowStock,
          ),
          isTrue,
        );
      },
    );
  });

  group('AdminInventoryViewModel - stock status thresholds', () {
    test('0 is Out of Stock', () {
      final product = db.products.first;
      db.updateStock(product.id, 0);
      expect(viewModel.stockStatusFor(product.id), StockStatus.outOfStock);
    });

    test('1 is Low Stock', () {
      final product = db.products.first;
      db.updateStock(product.id, 1);
      expect(viewModel.stockStatusFor(product.id), StockStatus.lowStock);
    });

    test('exactly the threshold is Low Stock', () {
      final product = db.products.first;
      db.updateStock(product.id, CommerceDatabase.lowStockThreshold);
      expect(viewModel.stockStatusFor(product.id), StockStatus.lowStock);
    });

    test('threshold + 1 is In Stock', () {
      final product = db.products.first;
      db.updateStock(product.id, CommerceDatabase.lowStockThreshold + 1);
      expect(viewModel.stockStatusFor(product.id), StockStatus.inStock);
    });
  });

  group('AdminInventoryViewModel - staged editing', () {
    test('plus increments the pending quantity', () {
      final product = db.getProductById('luna-accent-chair');
      viewModel.incrementQuantity(product.id);
      expect(
        viewModel.pendingQuantityFor(product.id),
        product.stockQuantity + 1,
      );
    });

    test('minus decrements the pending quantity', () {
      final product = db.getProductById('luna-accent-chair');
      viewModel.decrementQuantity(product.id);
      expect(
        viewModel.pendingQuantityFor(product.id),
        product.stockQuantity - 1,
      );
    });

    test('minus cannot go below zero', () {
      final product = db.getProductById('luna-accent-chair');
      viewModel.setPendingQuantityFromText(product.id, '0');
      viewModel.decrementQuantity(product.id);
      expect(viewModel.pendingQuantityFor(product.id), 0);
    });

    test('direct whole-number input stages the typed value', () {
      final product = db.getProductById('luna-accent-chair');
      viewModel.setPendingQuantityFromText(product.id, '42');
      expect(viewModel.pendingQuantityFor(product.id), 42);
      expect(viewModel.errorFor(product.id), isNull);
    });

    test('decimal input is rejected with an inline error', () {
      final product = db.getProductById('luna-accent-chair');
      final originalPending = viewModel.pendingQuantityFor(product.id);
      viewModel.setPendingQuantityFromText(product.id, '3.5');
      expect(viewModel.errorFor(product.id), contains('whole number'));
      // Last valid staged value is preserved rather than discarded.
      expect(viewModel.pendingQuantityFor(product.id), originalPending);
    });

    test('negative input is rejected with an inline error', () {
      final product = db.getProductById('luna-accent-chair');
      viewModel.setPendingQuantityFromText(product.id, '-2');
      expect(viewModel.errorFor(product.id), contains('negative'));
    });

    test('invalid text input is rejected with an inline error', () {
      final product = db.getProductById('luna-accent-chair');
      viewModel.setPendingQuantityFromText(product.id, 'abc');
      expect(viewModel.errorFor(product.id), isNotNull);
    });

    test('pending edits do not mutate the shared database until Save', () {
      final product = db.getProductById('luna-accent-chair');
      final originalStock = product.stockQuantity;
      viewModel.incrementQuantity(product.id);
      viewModel.incrementQuantity(product.id);
      expect(db.getProductById(product.id).stockQuantity, originalStock);
    });

    test(
      'Save commits the staged value through MockCommerceDatabase',
      () async {
        final product = db.getProductById('luna-accent-chair');
        viewModel.setPendingQuantityFromText(product.id, '3');
        final saved = await viewModel.saveProduct(product.id);
        expect(saved, isTrue);
        expect(db.getProductById(product.id).stockQuantity, 3);
      },
    );

    test('row dirty state clears after a successful save', () async {
      final product = db.getProductById('luna-accent-chair');
      viewModel.incrementQuantity(product.id);
      expect(viewModel.hasPendingChange(product.id), isTrue);

      await viewModel.saveProduct(product.id);
      expect(viewModel.hasPendingChange(product.id), isFalse);
      expect(
        viewModel.pendingQuantityFor(product.id),
        db.getProductById(product.id).stockQuantity,
      );
    });

    test(
      'a validation error blocks Save without touching the database',
      () async {
        final product = db.getProductById('luna-accent-chair');
        final originalStock = product.stockQuantity;
        viewModel.setPendingQuantityFromText(product.id, '-5');

        final saved = await viewModel.saveProduct(product.id);

        expect(saved, isFalse);
        expect(db.getProductById(product.id).stockQuantity, originalStock);
      },
    );

    test(
      'edits to one product never affect another product\'s pending state',
      () {
        final productA = db.getProductById('luna-accent-chair');
        final productB = db.getProductById('mens-oxford-shirt');
        final originalB = productB.stockQuantity;

        viewModel.setPendingQuantityFromText(productA.id, '7');

        expect(viewModel.pendingQuantityFor(productA.id), 7);
        expect(viewModel.pendingQuantityFor(productB.id), originalB);
        expect(viewModel.hasPendingChange(productB.id), isFalse);
      },
    );

    test('Last Updated is null until the first real inventory update, then '
        'reflects the stamped value', () async {
      final product = db.getProductById('luna-accent-chair');
      expect(product.lastStockUpdatedAt, isNull);
      expect(viewModel.lastUpdatedFor(product.id), isNull);

      viewModel.incrementQuantity(product.id);
      expect(viewModel.lastUpdatedFor(product.id), isNull);

      await viewModel.saveProduct(product.id);
      expect(viewModel.lastUpdatedFor(product.id), isNotNull);
      // Against the Mock the server stamp resolves synchronously, so the row
      // has already converged to the persisted value.
      expect(
        viewModel.lastUpdatedFor(product.id),
        db.getProductById(product.id).lastStockUpdatedAt,
      );
    });

    test('Phase 8.11: shows an optimistic "just now" stamp immediately after '
        'save, then converges to the authoritative server value without '
        'permanently masking it', () async {
      final deferredDb = _DeferredStampDb();
      final vm = AdminInventoryViewModel(deferredDb, MockCategoryRepository());
      addTearDown(vm.dispose);
      final product = deferredDb.getProductById('luna-accent-chair');

      vm.setPendingQuantityFromText(product.id, '9');
      final beforeSave = DateTime.now();
      expect(await vm.saveProduct(product.id), isTrue);

      // Quantity committed; server timestamp not resolved yet.
      expect(deferredDb.getProductById(product.id).stockQuantity, 9);
      expect(deferredDb.getProductById(product.id).lastStockUpdatedAt, isNull);

      // Optimistic client stamp is shown in the meantime.
      final optimistic = vm.lastUpdatedFor(product.id);
      expect(optimistic, isNotNull);
      expect(
        optimistic!.isBefore(beforeSave.subtract(const Duration(seconds: 1))),
        isFalse,
      );

      // The authoritative server-resolved timestamp lands via a later
      // snapshot.
      deferredDb.resolveServerStamp(product.id);
      final serverStamp = deferredDb
          .getProductById(product.id)
          .lastStockUpdatedAt;
      expect(serverStamp, isNotNull);

      // The row has converged to the persisted value and does not revert.
      expect(vm.lastUpdatedFor(product.id), serverStamp);
      deferredDb.notifyDummy();
      expect(vm.lastUpdatedFor(product.id), serverStamp);
    });

    test('Phase 8.11: a persisted lastStockUpdatedAt survives a screen reload '
        '(a fresh ViewModel) with no session edit', () async {
      final product = db.getProductById('luna-accent-chair');
      await db.updateStock(product.id, 4);
      final stamped = db.getProductById(product.id).lastStockUpdatedAt;
      expect(stamped, isNotNull);

      final reloaded = AdminInventoryViewModel(db, MockCategoryRepository());
      addTearDown(reloaded.dispose);
      expect(reloaded.lastUpdatedFor(product.id), stamped);
    });
  });

  group('AdminInventoryViewModel - cross-feature reactivity regression', () {
    test(
      'an Inventory save is immediately reflected by AdminDashboardViewModel',
      () async {
        final dashboardViewModel = AdminDashboardViewModel(db);
        addTearDown(dashboardViewModel.dispose);

        // Pick a product that is not currently in the low-stock bucket.
        final product = db.products.firstWhere(
          (p) =>
              stockStatusForQuantity(
                p.stockQuantity,
                CommerceDatabase.lowStockThreshold,
              ) !=
              StockStatus.lowStock,
        );
        final baselineLowStockCount = dashboardViewModel.lowStockProductsCount;

        viewModel.setPendingQuantityFromText(
          product.id,
          CommerceDatabase.lowStockThreshold.toString(),
        );
        await viewModel.saveProduct(product.id);

        expect(
          dashboardViewModel.lowStockProductsCount,
          baselineLowStockCount + 1,
        );
        expect(
          dashboardViewModel.lowStockProducts.any((p) => p.id == product.id) ||
              dashboardViewModel.lowStockProductsCount > 3,
          isTrue,
        );
      },
    );
  });
}
