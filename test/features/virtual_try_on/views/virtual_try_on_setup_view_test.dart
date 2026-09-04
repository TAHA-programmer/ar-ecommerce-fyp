import 'package:flutter/material.dart';
import 'package:twin_ar/core/data/mock_commerce_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/features/product_details/repositories/mock_product_details_repository.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/features/virtual_try_on/viewmodels/virtual_try_on_setup_viewmodel.dart';
import 'package:twin_ar/features/virtual_try_on/views/virtual_try_on_setup_view.dart';

void main() {
  Widget createTestWidget(String productId) {
    final repository = MockProductDetailsRepository(
      MockCommerceDatabase(),
      simulateDelay: false,
    );
    return MaterialApp(
      routes: {
        RouteNames.explore: (context) => const Scaffold(body: Text('Explore')),
        RouteNames.home: (context) => const Scaffold(body: Text('Home')),
      },
      home: Provider<ProductDetailsRepository>.value(
        value: repository,
        child: ChangeNotifierProvider(
          create: (context) => VirtualTryOnSetupViewModel(
            repository: repository,
            productId: productId,
          ),
          child: const VirtualTryOnSetupView(),
        ),
      ),
    );
  }

  testWidgets('Renders male variant correctly', (WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget('mens-oxford-shirt'));

    // Initial loading state
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    // Wait for product to load
    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Virtual Try-On'), findsOneWidget);
    expect(find.text('Men\'s Oxford Shirt'), findsOneWidget);
    expect(find.text('How Virtual Try-On works'), findsOneWidget);
    expect(find.text('Choose Camera'), findsOneWidget);
    expect(find.text('Position Yourself'), findsOneWidget);
    expect(find.text('Your Privacy Matters'), findsOneWidget);
    expect(find.text('Compatibility'), findsOneWidget);
    expect(find.text('Start Try-On'), findsOneWidget);
  });

  testWidgets('Renders female variant correctly', (WidgetTester tester) async {
    await tester.pumpWidget(createTestWidget('womens-blazer'));

    await tester.pumpAndSettle(const Duration(seconds: 1));

    expect(find.text('Virtual Try-On'), findsOneWidget); // Body title
    expect(find.text('Women\'s Blazer'), findsOneWidget);
    expect(find.text('Choose your camera'), findsOneWidget);
    expect(find.text('Compatibility Note'), findsOneWidget);
    expect(find.text('Start Try-On'), findsOneWidget);
  });
}
