import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/features/admin/dashboard/viewmodels/admin_dashboard_viewmodel.dart';
import 'package:twin_ar/core/utils/currency_formatter.dart';

import 'package:twin_ar/core/models/order/order_model.dart';
import 'package:twin_ar/core/models/order/payment_record.dart';
import 'package:twin_ar/core/models/product/product_model.dart';

class EmptyMockCommerceDatabase extends MockCommerceDatabase {
  @override
  List<ProductModel> get products => [];
  @override
  List<OrderModel> get orders => [];
  @override
  List<PaymentRecord> get payments => [];
}

void main() {
  late MockCommerceDatabase db;
  late AdminDashboardViewModel viewModel;

  setUp(() {
    db = MockCommerceDatabase();
    viewModel = AdminDashboardViewModel(db);
  });

  group('AdminDashboardViewModel Tests', () {
    test('Derived metrics from shared database correctly', () {
      final totalProducts = db.products.length;
      final totalOrders = db.orders.length;

      expect(viewModel.totalProducts, equals(totalProducts));
      expect(viewModel.totalOrders, equals(totalOrders));

      final pendingOrders = db.orders
          .where((o) => o.orderStatus == OrderStatus.pending)
          .length;
      expect(viewModel.pendingOrdersCount, equals(pendingOrders));

      expect(viewModel.lowStockProducts.length, lessThanOrEqualTo(3));

      final successPayments = db.payments
          .where((p) => p.status == PaymentStatus.paid)
          .length;
      expect(viewModel.successfulPaymentsCount, equals(successPayments));

      final failedPayments = db.payments
          .where((p) => p.status == PaymentStatus.failed)
          .length;
      expect(viewModel.failedPaymentsCount, equals(failedPayments));
    });

    test(
      'low stock metric counts all items while preview stays capped at 3',
      () {
        final products = db.products.take(5).toList();
        for (var index = 0; index < products.length; index++) {
          db.updateStock(products[index].id, index + 1);
        }

        expect(viewModel.lowStockProductsCount, 5);
        expect(viewModel.lowStockProducts, hasLength(3));
        expect(
          viewModel.lowStockProducts.map((product) => product.stockQuantity),
          orderedEquals([1, 2, 3]),
        );
      },
    );

    test('Revenue only counts successful payments', () {
      double expectedRevenue = 0.0;
      for (final p in db.payments) {
        if (p.status == PaymentStatus.paid) {
          expectedRevenue += p.amount;
        }
      }
      expect(viewModel.totalRevenue, equals(expectedRevenue));
    });

    test('Zero state is safe', () {
      final emptyDb = EmptyMockCommerceDatabase();

      // Need to notify listeners or recreate view model to get updated state
      viewModel = AdminDashboardViewModel(emptyDb);

      expect(viewModel.totalProducts, equals(0));
      expect(viewModel.totalOrders, equals(0));
      expect(viewModel.totalRevenue, equals(0.0));
      expect(viewModel.successfulPaymentsCount, equals(0));
      expect(viewModel.recentOrders.length, equals(0));
    });

    test('Recent Orders newest-first', () {
      final sortedOrders = viewModel.recentOrders;
      for (int i = 0; i < sortedOrders.length - 1; i++) {
        final current = sortedOrders[i].orderDate;
        final next = sortedOrders[i + 1].orderDate;
        expect(current.isAfter(next) || current.isAtSameMomentAs(next), isTrue);
      }
    });

    test('Recently Added Products newest-first', () {
      final sortedProducts = viewModel.recentlyAddedProducts;
      for (int i = 0; i < sortedProducts.length - 1; i++) {
        final current = sortedProducts[i].addedDate;
        final next = sortedProducts[i + 1].addedDate;
        expect(current.isAfter(next) || current.isAtSameMomentAs(next), isTrue);
      }
    });
  });

  group('CurrencyFormatter Tests', () {
    test('Formats correctly with Rs', () {
      expect(CurrencyFormatter.format(1000.0), equals('Rs 1,000'));
      expect(CurrencyFormatter.format(0.0), equals('Rs 0'));
      expect(CurrencyFormatter.format(999999.0), equals('Rs 999,999'));
    });

    test('Does not contain \$ or ₹', () {
      final formatted = CurrencyFormatter.format(1000.0);
      expect(formatted.contains('\$'), isFalse);
      expect(formatted.contains('₹'), isFalse);
    });
  });
}
