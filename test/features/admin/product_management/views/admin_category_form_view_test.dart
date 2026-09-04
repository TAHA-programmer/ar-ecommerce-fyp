import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/core/data/category_repository.dart';
import 'package:twin_ar/core/data/mock_category_repository.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/services/mock_storage_service.dart';
import 'package:twin_ar/core/services/storage_service.dart';
import 'package:twin_ar/features/admin/product_management/views/admin_category_form_view.dart';

void main() {
  Widget buildApp({String? categoryId, CategoryRepository? repository}) {
    return MaterialApp(
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<CategoryRepository>.value(
            value: repository ?? MockCategoryRepository(),
          ),
          Provider<StorageService>(create: (_) => MockStorageService()),
        ],
        child: AdminCategoryFormView(categoryId: categoryId),
      ),
    );
  }

  group('AdminCategoryFormView - Add mode', () {
    testWidgets('renders the Add Category title and every field with its '
        'subtext', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Add Category'), findsWidgets); // AppBar + button
      expect(find.text('Name'), findsOneWidget);
      expect(find.text('Kind'), findsOneWidget);
      expect(find.text('Image'), findsOneWidget);

      // Name subtext clarifies unlimited categories are allowed.
      expect(
        find.textContaining('not limited to the Kind list'),
        findsOneWidget,
      );
      // Kind subtext clarifies its real purpose (AR eligibility), directly
      // addressing "isn't this just another category field?" confusion.
      expect(find.textContaining('Not another category field'), findsOneWidget);
      expect(find.textContaining('Room AR'), findsOneWidget);

      // The card-based layout is taller than the default test surface, so
      // the Status card (last in the list) needs a scroll before it's even
      // built - the ListView's sliver cache extent doesn't cover it yet.
      await tester.drag(find.byType(ListView).first, const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(find.text('Status'), findsOneWidget);
    });

    testWidgets('the Kind dropdown is enabled and defaults to a real value '
        '(never .all)', (tester) async {
      await tester.pumpWidget(buildApp());
      await tester.pumpAndSettle();

      expect(
        find.byType(DropdownButtonFormField<ProductCategory>),
        findsOneWidget,
      );
      expect(find.text('Furniture'), findsWidgets); // dropdown's current value
      expect(find.text('All'), findsNothing);
    });
  });

  group('AdminCategoryFormView - Edit mode', () {
    testWidgets('renders the Edit Category title, pre-filled name, and '
        'read-only Key/Kind with their own explanatory subtext', (
      tester,
    ) async {
      final repo = MockCategoryRepository();
      await tester.pumpWidget(
        buildApp(categoryId: 'furniture', repository: repo),
      );
      await tester.pumpAndSettle();

      expect(find.text('Edit Category'), findsOneWidget);
      expect(find.text('Furniture'), findsWidgets); // pre-filled name + kind

      expect(find.text('Key'), findsOneWidget);
      expect(find.textContaining('never changes'), findsOneWidget);
      expect(
        find.textContaining(
          'Kind cannot be changed after a category is created',
        ),
        findsOneWidget,
      );
    });

    testWidgets('a nonexistent category id shows a clean error screen, not '
        'a crash', (tester) async {
      await tester.pumpWidget(buildApp(categoryId: 'does-not-exist'));
      await tester.pumpAndSettle();

      expect(find.text('Category not found.'), findsOneWidget);
    });
  });
}
