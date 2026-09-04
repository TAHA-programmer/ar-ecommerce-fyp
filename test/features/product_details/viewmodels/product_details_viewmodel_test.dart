import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/features/product_details/viewmodels/product_details_viewmodel.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_size.dart';

void main() {
  late MockCommerceDatabase db;
  late MockProductDetailsRepository repository;
  late CustomerShoppingState shoppingState;
  late MockCategoryRepository categoryRepository;

  setUp(() {
    db = MockCommerceDatabase();
    repository = MockProductDetailsRepository(db, simulateDelay: false);
    shoppingState = CustomerShoppingState(
      MockFavoritesRepository(),
      MockCartRepository(),
    );
    categoryRepository = MockCategoryRepository();
  });

  group('ProductDetailsViewModel Tests', () {
    test('load success', () async {
      final viewModel = ProductDetailsViewModel(
        repository: repository,
        shoppingState: shoppingState,
        categoryRepository: categoryRepository,
        productId: 'luna-accent-chair',
      );

      expect(viewModel.isLoading, isTrue);
      await Future.delayed(const Duration(milliseconds: 700));
      expect(viewModel.isLoading, isFalse);
      expect(viewModel.product, isNotNull);
      expect(viewModel.error, isNull);
    });

    test('unknown-product error', () async {
      final viewModel = ProductDetailsViewModel(
        repository: repository,
        shoppingState: shoppingState,
        categoryRepository: categoryRepository,
        productId: 'invalid',
      );

      await Future.delayed(const Duration(milliseconds: 700));
      expect(viewModel.error, isNotNull);
      expect(viewModel.product, isNull);
    });

    test(
      'initial quantity 1, increment, decrement, cannot go below 1',
      () async {
        final viewModel = ProductDetailsViewModel(
          repository: repository,
          shoppingState: shoppingState,
          categoryRepository: categoryRepository,
          productId: 'luna-accent-chair',
        );

        expect(viewModel.selectedQuantity, 1);

        viewModel.incrementQuantity();
        expect(viewModel.selectedQuantity, 2);

        viewModel.decrementQuantity();
        expect(viewModel.selectedQuantity, 1);

        viewModel.decrementQuantity();
        expect(viewModel.selectedQuantity, 1);
      },
    );

    test('initial selected color and size, and changes', () async {
      final viewModel = ProductDetailsViewModel(
        repository: repository,
        shoppingState: shoppingState,
        categoryRepository: categoryRepository,
        productId: 'mens-oxford-shirt',
      );

      await Future.delayed(const Duration(milliseconds: 700));

      expect(viewModel.selectedColor, ProductColorOption.blue);
      expect(viewModel.selectedSize, ProductSize.m);

      viewModel.selectColor(ProductColorOption.black);
      expect(viewModel.selectedColor, ProductColorOption.black);

      viewModel.selectSize(ProductSize.l);
      expect(viewModel.selectedSize, ProductSize.l);
    });

    test('gallery index', () {
      final viewModel = ProductDetailsViewModel(
        repository: repository,
        shoppingState: shoppingState,
        categoryRepository: categoryRepository,
        productId: 'luna-accent-chair',
      );

      expect(viewModel.activeGalleryIndex, 0);
      viewModel.setActiveGalleryIndex(2);
      expect(viewModel.activeGalleryIndex, 2);
    });

    test('favorite delegation', () {
      final viewModel = ProductDetailsViewModel(
        repository: repository,
        shoppingState: shoppingState,
        categoryRepository: categoryRepository,
        productId: 'luna-accent-chair',
      );

      expect(viewModel.isFavorite, isFalse);
      viewModel.toggleFavorite();
      expect(viewModel.isFavorite, isTrue);
      expect(shoppingState.isFavorite('luna-accent-chair'), isTrue);
    });

    test(
      'categoryDisplayName resolves the real category name when '
      'available, and falls back to categoryKind.label when the '
      'category can\'t be resolved (deleted/inactive-for-this-session)',
      () async {
        final viewModel = ProductDetailsViewModel(
          repository: repository,
          shoppingState: shoppingState,
          categoryRepository: categoryRepository,
          productId: 'luna-accent-chair',
        );
        await Future.delayed(const Duration(milliseconds: 700));

        // luna-accent-chair's categoryId resolves against the default mock
        // categories - renaming the category (no product write at all)
        // changes the displayed text immediately, proving this is a live
        // resolution, not a denormalized/cached name.
        final furniture = categoryRepository.categories.firstWhere(
          (c) => c.categoryId == 'furniture',
        );
        await categoryRepository.updateCategory(
          furniture.copyWith(name: 'Home Furniture'),
        );
        expect(viewModel.categoryDisplayName, 'Home Furniture');

        // Simulate the category becoming unresolvable in this session
        // (deleted, or inactive on a customer-role session) - falls back to
        // the denormalized categoryKind.label ("Furniture") instead of going
        // blank or showing stale text.
        categoryRepository.debugSetCategories(const []);
        expect(viewModel.categoryDisplayName, 'Furniture');
      },
    );

    test('quantity-aware cart add', () {
      final viewModel = ProductDetailsViewModel(
        repository: repository,
        shoppingState: shoppingState,
        categoryRepository: categoryRepository,
        productId: 'luna-accent-chair',
      );

      expect(shoppingState.cartCount, 0);

      viewModel.incrementQuantity(); // quantity = 2
      viewModel.addToCart();

      expect(shoppingState.cartCount, 2);
    });

    group('Phase 8.11a - stock exposure & guards', () {
      Future<ProductDetailsViewModel> loadedVm(String productId) async {
        final vm = ProductDetailsViewModel(
          repository: repository,
          shoppingState: shoppingState,
          categoryRepository: categoryRepository,
          productId: productId,
        );
        await Future.delayed(const Duration(milliseconds: 10));
        return vm;
      }

      test('availableStock is wired to the real Firestore-backed product '
          'data, not hardcoded, and refresh() picks up a change', () async {
        await db.updateStock('luna-accent-chair', 6);
        final vm = await loadedVm('luna-accent-chair');

        expect(vm.availableStock, 6);
        expect(vm.isOutOfStock, isFalse);
        expect(vm.product!.stockQuantity, 6);

        await db.updateStock('luna-accent-chair', 0);
        await vm.refresh();
        expect(vm.availableStock, 0);
        expect(vm.isOutOfStock, isTrue);
      });

      test('out-of-stock: addToCart is blocked in the ViewModel (not only by '
          'a disabled button) and nothing is added', () async {
        await db.updateStock('luna-accent-chair', 0);
        final vm = await loadedVm('luna-accent-chair');

        expect(vm.isOutOfStock, isTrue);
        final error = await vm.addToCart();
        expect(error, contains('out of stock'));
        expect(shoppingState.cartCount, 0);
      });

      test('low stock (> 0) stays purchasable', () async {
        await db.updateStock('luna-accent-chair', 2);
        final vm = await loadedVm('luna-accent-chair');

        expect(vm.isOutOfStock, isFalse);
        final error = await vm.addToCart();
        expect(error, isNull);
        expect(shoppingState.cartCount, 1);
      });

      test('quantity cannot exceed available stock: increment is capped and '
          'returns a clean message at the limit', () async {
        await db.updateStock('luna-accent-chair', 3);
        final vm = await loadedVm('luna-accent-chair');

        expect(vm.selectedQuantity, 1);
        expect(vm.incrementQuantity(), isNull); // 2
        expect(vm.incrementQuantity(), isNull); // 3
        expect(vm.selectedQuantity, 3);
        expect(vm.canIncrementQuantity, isFalse);

        final blocked = vm.incrementQuantity(); // would be 4
        expect(blocked, contains('Only 3 available'));
        expect(vm.selectedQuantity, 3);
      });

      test('a refresh that reduces stock clamps the selected quantity so a '
          'stale over-limit selection cannot slip through', () async {
        await db.updateStock('luna-accent-chair', 2);
        final vm = await loadedVm('luna-accent-chair');
        vm.incrementQuantity(); // 2 (ok)
        expect(vm.selectedQuantity, 2);

        await db.updateStock('luna-accent-chair', 1);
        await vm.refresh();

        expect(vm.selectedQuantity, 1);
        expect(vm.canIncrementQuantity, isFalse);
        final error = await vm.addToCart();
        expect(error, isNull);
        expect(shoppingState.cartCount, 1);
      });
    });
  });
}
