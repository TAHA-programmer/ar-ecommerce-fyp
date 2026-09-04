import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/category_repository.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/features/admin/inventory/widgets/admin_inventory_product_card.dart';
import 'package:twin_ar/features/admin/inventory/widgets/admin_inventory_filter_bar.dart';
import 'package:twin_ar/features/admin/inventory/widgets/stock_quantity_control.dart';
import 'package:twin_ar/features/admin/views/admin_inventory_view.dart';
import 'package:twin_ar/features/admin/widgets/admin_bottom_navigation.dart';

void main() {
  late MockCommerceDatabase db;

  Widget buildTestWidget() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CommerceDatabase>.value(value: db),
        ChangeNotifierProvider<CategoryRepository>(
          create: (_) => MockCategoryRepository(),
        ),
        ChangeNotifierProvider<AuthSessionState>(
          create: (_) => AuthSessionState(),
        ),
      ],
      child: const MaterialApp(home: Scaffold(body: AdminInventoryView())),
    );
  }

  setUp(() {
    db = MockCommerceDatabase();
  });

  group('AdminInventoryView', () {
    testWidgets('replaces the placeholder with the real screen', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Inventory Management'), findsOneWidget);
      expect(
        find.text('Inventory Management will be implemented later.'),
        findsNothing,
      );
    });

    testWidgets('shows the Inventory tab selected in the Admin bottom nav', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      final nav = tester.widget<AdminBottomNavigation>(
        find.byType(AdminBottomNavigation),
      );
      expect(nav.currentIndex, 2);
    });

    testWidgets('renders search, category filter, and low-stock controls', (
      tester,
    ) async {
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.byType(AdminInventoryFilterBar), findsOneWidget);
      expect(find.byType(TextField), findsWidgets);
      expect(find.byType(DropdownButton<ProductCategory>), findsOneWidget);
      expect(find.byType(Switch), findsOneWidget);
      expect(find.textContaining('Total Products:'), findsOneWidget);
    });

    testWidgets(
      'renders cards sourced from the real shared database, not fake data',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        // The Summary count and the rendered rows must reflect the live
        // MockCommerceDatabase product count (51 seeded products), never a
        // hardcoded Figma-sample count.
        expect(
          find.text('Total Products: ${db.products.length}'),
          findsOneWidget,
        );
        expect(find.byType(AdminInventoryProductCard), findsWidgets);
        // The first two seeded products (out of the ListView's lazily-built
        // viewport) must be genuine MockCommerceDatabase products.
        expect(find.text('Luna Right-Chaise Sectional Sofa'), findsOneWidget);
        expect(find.text('Boho Woven Rug'), findsOneWidget);
      },
    );

    testWidgets('search narrows the visible rows', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, 'Luna Accent Chair');
      await tester.pumpAndSettle();

      expect(find.byType(AdminInventoryProductCard), findsOneWidget);
      expect(
        find.widgetWithText(AdminInventoryProductCard, 'Luna Accent Chair'),
        findsOneWidget,
      );
    });

    testWidgets('shows a themed empty state when no product matches', (
      tester,
    ) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        'no-such-product-xyz',
      );
      await tester.pumpAndSettle();

      expect(find.text('No products found'), findsOneWidget);
      expect(find.byType(AdminInventoryProductCard), findsNothing);
    });

    testWidgets('manufactured low-stock product shows the Low Stock badge', (
      tester,
    ) async {
      final lowStockProduct = db.products.first;
      db.updateStock(lowStockProduct.id, CommerceDatabase.lowStockThreshold);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byType(TextField).first,
        lowStockProduct.title,
      );
      await tester.pumpAndSettle();

      expect(find.text('Low Stock'), findsWidgets);
    });

    testWidgets('Low Stock Only toggle filters down to the low-stock bucket', (
      tester,
    ) async {
      final lowStockProduct = db.products.first;
      db.updateStock(lowStockProduct.id, CommerceDatabase.lowStockThreshold);

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(find.byType(AdminInventoryProductCard), findsOneWidget);
      expect(find.text(lowStockProduct.title), findsOneWidget);
    });

    testWidgets(
      'a no-match search under a squeezed (keyboard-open) viewport does not overflow',
      (tester) async {
        // Regression: reproduces a keyboard-shrunk viewport (e.g. a small
        // device with the on-screen keyboard open) while showing the empty
        // state, which previously triggered a bottom RenderFlex overflow.
        // addTearDown guarantees the surface size resets even if an
        // assertion below fails, so this can never leak into later tests.
        addTearDown(() => tester.binding.setSurfaceSize(null));
        await tester.binding.setSurfaceSize(const Size(360, 500));
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.enterText(find.byType(TextField).first, 'furniti');
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.text('No products found'), findsOneWidget);
      },
    );

    testWidgets(
      'the stock stepper stays compact instead of stretching across the row',
      (tester) async {
        await tester.pumpWidget(buildTestWidget());
        await tester.pumpAndSettle();

        await tester.enterText(
          find.byType(TextField).first,
          'Luna Accent Chair',
        );
        await tester.pumpAndSettle();

        final cardWidth = tester
            .getSize(find.byType(AdminInventoryProductCard))
            .width;
        final controlWidth = tester
            .getSize(find.byType(StockQuantityControl))
            .width;

        // The stepper must size to its content, not stretch to fill the
        // card's width via a leftover Expanded wrapper.
        expect(controlWidth, lessThan(cardWidth * 0.6));
      },
    );

    testWidgets('incrementing and saving commits through the shared database', (
      tester,
    ) async {
      final product = db.getProductById('luna-accent-chair');
      final originalStock = product.stockQuantity;

      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField).first, product.title);
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.add).first);
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('inventory_save_button')));
      await tester.pumpAndSettle();

      expect(db.getProductById(product.id).stockQuantity, originalStock + 1);
      expect(find.text('Stock updated successfully'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4)); // let AppToast finish
      await tester.pumpAndSettle();
    });
  });
}
