import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/theme/app_typography.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/features/virtual_try_on/viewmodels/virtual_try_on_setup_viewmodel.dart';
import 'package:twin_ar/features/virtual_try_on/views/virtual_try_on_setup_view.dart';

import '../virtual_try_on_test_helpers.dart';

void main() {
  Widget createTestWidget(
    String productId,
    ProductDetailsRepository repository,
  ) {
    return MaterialApp(
      routes: {
        RouteNames.explore: (context) => const Scaffold(body: Text('Explore')),
        RouteNames.home: (context) => const Scaffold(body: Text('Home')),
        RouteNames.login: (context) => const Scaffold(body: Text('Login')),
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

  testWidgets('renders an eligible product with consent gating Start', (
    tester,
  ) async {
    final repository = FakeVtoProductDetailsRepository(
      product: buildEligibleVtoProduct(),
      productId: kEligibleVtoProductId,
    );
    await tester.pumpWidget(
      createTestWidget(kEligibleVtoProductId, repository),
    );

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    await tester.pumpAndSettle();

    expect(find.text('Test Shirt'), findsOneWidget);
    expect(find.text('How Virtual Try-On Works'), findsOneWidget);
    expect(find.text('Position Yourself'), findsOneWidget);
    expect(find.text('Start Try-On'), findsOneWidget);
    // No front-camera affordance anywhere on this screen.
    expect(find.textContaining('Front Camera'), findsNothing);

    // The "Before you continue" consent statement is a real theme text
    // style, one step smaller than the app-wide checkbox default, but keeps
    // the full-strength primary text colour rather than dimming to
    // secondary/caption grey — the privacy information should not read as
    // less prominent than any other body text on the screen.
    expect(find.text('Before you continue'), findsOneWidget);
    final consentTextFinder = find.textContaining(
      'I understand my photo will be sent to Google Gemini',
    );
    expect(consentTextFinder, findsOneWidget);
    final consentText = tester.widget<Text>(consentTextFinder);
    expect(consentText.style?.fontSize, AppTypography.bodySmall.fontSize);
    expect(consentText.style?.fontFamily, AppTypography.bodySmall.fontFamily);
    expect(consentText.style?.color, AppColors.textPrimary);
    // Not weakened: still names Gemini, the deletion timing, and the
    // fit/size disclaimer.
    expect(
      consentText.data,
      allOf(
        contains('Google Gemini'),
        contains('deleted right after the preview is generated'),
        contains('24 hours'),
        contains('not a'),
      ),
    );

    final startButtonFinder = find.widgetWithText(
      ElevatedButton,
      'Start Try-On',
    );
    ElevatedButton startButton = tester.widget(startButtonFinder);
    expect(
      startButton.onPressed,
      isNull,
      reason: 'disabled until consent is checked',
    );

    await tester.ensureVisible(find.byType(Checkbox));
    await tester.pumpAndSettle();
    await tester.tap(find.byType(Checkbox));
    await tester.pumpAndSettle();

    startButton = tester.widget(startButtonFinder);
    expect(startButton.onPressed, isNotNull);
  });

  testWidgets('shows an error state for an ineligible product', (tester) async {
    final repository = FakeVtoProductDetailsRepository(
      product: buildNonVtoProduct(),
      productId: 'non-vto-product',
    );
    await tester.pumpWidget(createTestWidget('non-vto-product', repository));

    await tester.pumpAndSettle();

    expect(
      find.text("Virtual Try-On isn't available for this product."),
      findsOneWidget,
    );
    expect(find.text('Start Try-On'), findsNothing);
  });
}
