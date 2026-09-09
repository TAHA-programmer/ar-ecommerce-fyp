import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_image_ref.dart';
import 'package:twin_ar/core/models/product/product_model.dart';
import 'package:twin_ar/core/models/product/product_publication_status.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/product_details/repositories/mock_recently_viewed_repository.dart';
import 'package:twin_ar/features/recently_viewed/viewmodels/recently_viewed_viewmodel.dart';

ProductModel _product(
  String id, {
  bool isActive = true,
  ProductPublicationStatus status = ProductPublicationStatus.published,
}) => ProductModel(
  id: id,
  sku: 'SKU-$id',
  title: id,
  description: '',
  categoryId: 'decor',
  categoryKind: ProductCategory.decor,
  subcategory: 'Sub',
  priceAmount: 1000,
  stockQuantity: 5,
  isActive: isActive,
  publicationStatus: status,
  mainImage: const ProductImageRef(path: 'assets/x.png'),
  experienceType: ProductExperienceType.none,
  addedDate: DateTime(2026, 1, 1),
  deliveryEstimate: '3-5 days',
);

class _Db extends CommerceDatabase {
  final List<ProductModel> _p = [];
  @override
  List<ProductModel> get products => List.unmodifiable(_p);
  @override
  List<OrderModel> get orders => const [];
  @override
  List<PaymentRecord> get payments => const [];
  @override
  ProductModel getProductById(String id) =>
      _p.firstWhere((p) => p.id == id, orElse: () => throw StateError(id));
  @override
  Future<void> addProduct(ProductModel product) async {
    _p.add(product);
    notifyListeners();
  }

  @override
  Future<void> updateProduct(ProductModel product) async {
    final i = _p.indexWhere((p) => p.id == product.id);
    if (i >= 0) _p[i] = product;
    notifyListeners();
  }

  @override
  Future<void> setProductActive(String productId, bool isActive) async {}
  @override
  Future<void> updateStock(String productId, int newStockQuantity) async {}
  @override
  Future<void> deleteProduct(String productId) async {
    _p.removeWhere((p) => p.id == productId);
    notifyListeners();
  }

  @override
  Future<void> updateOrderStatus(String orderId, OrderStatus newStatus) async {}
}

CustomerShoppingState _shopping() =>
    CustomerShoppingState(MockFavoritesRepository(), MockCartRepository());

RecentlyViewedViewModel _vm(_Db db, MockRecentlyViewedRepository rv) =>
    RecentlyViewedViewModel(
      repository: rv,
      db: db,
      shoppingState: _shopping(),
      productDetailsRepository: MockProductDetailsRepository(
        MockCommerceDatabase(),
        simulateDelay: false,
      ),
    );

void main() {
  test('resolves history newest-first against the cache, deduped', () async {
    final db = _Db();
    for (final id in ['p1', 'p2', 'p3']) {
      await db.addProduct(_product(id));
    }
    final rv = MockRecentlyViewedRepository();
    for (final id in ['p1', 'p2', 'p3', 'p1']) {
      await rv.recordView(id);
    }
    final vm = _vm(db, rv);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(vm.products.map((p) => p.id).toList(), ['p1', 'p3', 'p2']);
    expect(vm.isLoading, false);
    expect(vm.isEmpty, false);
  });

  test('drops deleted / draft / inactive products', () async {
    final db = _Db();
    await db.addProduct(_product('live'));
    await db.addProduct(
      _product('draft', status: ProductPublicationStatus.draft),
    );
    await db.addProduct(_product('inactive', isActive: false));
    final rv = MockRecentlyViewedRepository()
      ..recordView('live')
      ..recordView('draft')
      ..recordView('inactive')
      ..recordView('deleted-long-ago');
    final vm = _vm(db, rv);
    await Future<void>.delayed(const Duration(milliseconds: 5));

    expect(vm.products.map((p) => p.id).toList(), ['live']);
  });

  test('reactively drops a product that gets unpublished', () async {
    final db = _Db();
    await db.addProduct(_product('a'));
    await db.addProduct(_product('b'));
    final rv = MockRecentlyViewedRepository()
      ..recordView('a')
      ..recordView('b');
    final vm = _vm(db, rv);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(vm.products.length, 2);

    await db.updateProduct(db.getProductById('a').copyWith(isActive: false));
    expect(vm.products.map((p) => p.id).toList(), ['b']);
  });

  test('empty history → isEmpty, not an error', () async {
    final vm = _vm(_Db(), MockRecentlyViewedRepository(signedIn: false));
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(vm.isEmpty, true);
    expect(vm.hasError, false);
    expect(vm.products, isEmpty);
  });

  test('a read failure with nothing resolved surfaces as hasError', () async {
    final vm = _vm(_Db(), MockRecentlyViewedRepository()..throwOnRead = true);
    await Future<void>.delayed(const Duration(milliseconds: 5));
    expect(vm.hasError, true);
    expect(vm.isEmpty, false); // an error is not an "empty" state
  });
}
