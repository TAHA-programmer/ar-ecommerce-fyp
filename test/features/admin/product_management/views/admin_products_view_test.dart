import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/app_router.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/data/category_repository.dart';
import 'package:twin_ar/core/data/commerce_database.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/core/services/storage_service.dart';
import 'package:twin_ar/features/admin/product_management/viewmodels/admin_category_form_viewmodel.dart';
import 'package:twin_ar/features/admin/product_management/views/admin_category_form_view.dart';
import 'package:twin_ar/features/admin/product_management/widgets/admin_category_card.dart';
import 'package:twin_ar/features/admin/product_management/widgets/admin_product_card.dart';
import 'package:twin_ar/features/admin/views/admin_products_view.dart';

/// A category image is now compulsory on save, but the real image picker
/// opens a native file chooser that can't be driven in a widget test - this
/// stages an image directly on the ViewModel instead, mirroring the same
/// direct-ViewModel-access pattern already used for other not-UI-drivable
/// setup in `admin_product_form_test.dart`.
File _tempCategoryImageFile() {
  final dir = Directory.systemTemp.createTempSync('twinar-category-test-');
  final file = File('${dir.path}/category.png');
  file.writeAsBytesSync(List.filled(128, 1));
  return file;
}

void main() {
  Widget buildTestWidget({CategoryRepository? categoryRepository}) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<CommerceDatabase>(
          create: (_) => MockCommerceDatabase(),
        ),
        ChangeNotifierProvider<CategoryRepository>(
          create: (_) => categoryRepository ?? MockCategoryRepository(),
        ),
        Provider<StorageService>(create: (_) => MockStorageService()),
        ChangeNotifierProvider<AuthSessionState>(
          create: (_) => AuthSessionState(),
        ),
      ],
      // onGenerateRoute is wired in (matching the real app) because
      // "+ Add Category"/category-card "Edit" now navigate to a real,
      // separately-routed screen (AdminCategoryFormView) instead of opening
      // a dialog - see AdminCategoryFormViewModel's doc comment for why it
      // must be a real route rather than a dialog on this route's provider.
      child: MaterialApp(
        home: const Scaffold(body: AdminProductsView()),
        onGenerateRoute: AppRouter.onGenerateRoute,
      ),
    );
  }

  group('AdminProductsView', () {
    testWidgets('renders products and header', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Products'), findsWidgets); // Header and Mode Selector
      expect(find.text('Categories'), findsOneWidget); // Mode Selector
      expect(find.byType(TextField), findsOneWidget); // Search bar
      expect(find.byType(AdminProductCard), findsWidgets);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('search filters list in ui', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), 'Velvet');
      await tester.pumpAndSettle();

      expect(find.text('Velvet Armchair'), findsWidgets);
      expect(find.text('Luna Right-Chaise Sectional Sofa'), findsNothing);
    });

    testWidgets('switching to categories mode shows categories UI', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap Categories mode
      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      // Should show category cards
      expect(find.byType(AdminCategoryCard), findsWidgets);
      expect(find.text('Categories'), findsWidgets);

      // Look for a known category
      expect(find.text('Furniture'), findsOneWidget);
      expect(find.text('Clothing'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('editing a category navigates to a real screen and renames '
        'it', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit').first);
      await tester.pumpAndSettle();

      // Should have navigated to a real screen, not a dialog.
      expect(find.byType(AdminCategoryFormView), findsOneWidget);
      expect(find.text('Edit Category'), findsOneWidget);

      // The card-based layout puts the Status card (with the Switch) below
      // the fold on a small screen - it isn't even built yet (outside the
      // ListView's sliver cache extent), so scroll before looking for it.
      // Scope to the form screen's own ListView - the products list
      // underneath is still mounted and has one too.
      final formListView = find.descendant(
        of: find.byType(AdminCategoryFormView),
        matching: find.byType(ListView),
      );
      await tester.drag(formListView, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.byType(Switch), findsOneWidget);
      await tester.tap(find.byType(Switch));
      // The seeded mock category has no image by default - now compulsory
      // on every save, including edit. Storage is mocked above, so this
      // stages and "uploads" safely without touching real Firebase.
      Provider.of<AdminCategoryFormViewModel>(
        tester.element(find.byType(Switch)),
        listen: false,
      ).setImageFile(_tempCategoryImageFile());
      await tester.tap(find.text('Update'));
      await tester.pumpAndSettle();

      // Back on the list, the category now shows Inactive.
      expect(find.byType(AdminCategoryFormView), findsNothing);
      expect(find.text('Inactive'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4)); // AppToast timer
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('Add Category navigates to a real screen, not a placeholder '
        'toast', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Add Category'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminCategoryFormView), findsOneWidget);
      expect(find.text('Add Category'), findsWidgets);
      expect(find.text('Coming soon in backend'), findsNothing);

      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('adding a category via the screen creates it and shows it '
        'in the list', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add Category'));
      await tester.pumpAndSettle();

      // Target the field within the new screen specifically - the previous
      // route's own search TextField may still be present in the widget
      // tree beneath it.
      final nameField = find.descendant(
        of: find.byType(AdminCategoryFormView),
        matching: find.byType(TextField),
      );
      await tester.enterText(nameField, 'Outdoor');
      // nameField's element is a descendant of the ChangeNotifierProvider
      // AdminCategoryFormView creates internally, so it's a valid context
      // to read the ViewModel from - the view's own element is not (the
      // provider is created inside its build(), not above it).
      Provider.of<AdminCategoryFormViewModel>(
        tester.element(nameField),
        listen: false,
      ).setImageFile(_tempCategoryImageFile());
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(find.byType(AdminCategoryFormView), findsNothing);
      // The new category sorts last (highest sortOrder) and may be below
      // the fold on a small screen - scroll the list to find it. Finders
      // are re-evaluated fresh each call, so re-querying find.byType(
      // ListView) every iteration avoids relying on a stale Element
      // reference across pumps.
      for (var i = 0; i < 6; i++) {
        if (find.text('Outdoor').evaluate().isNotEmpty) break;
        await tester.drag(find.byType(ListView).first, const Offset(0, -300));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(find.text('Outdoor'), findsOneWidget);

      await tester.pump(const Duration(seconds: 4));
      await tester.binding.setSurfaceSize(null);
    });

    testWidgets('a seeded category cannot be deleted', (tester) async {
      await tester.binding.setSurfaceSize(const Size(360, 800));
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      await tester.tap(find.text('Categories'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Delete').first);
      await tester.pumpAndSettle();

      expect(find.text('Cannot Delete Category'), findsOneWidget);
      expect(find.textContaining('built-in'), findsOneWidget);

      await tester.binding.setSurfaceSize(null);
    });
  });
}
