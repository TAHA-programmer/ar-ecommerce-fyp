import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/app/viewmodels/customer_shopping_state.dart';
import 'package:twin_ar/core/theme/app_colors.dart';
import 'package:twin_ar/core/data/mock_cart_repository.dart';
import 'package:twin_ar/core/data/mock_favorites_repository.dart';
import 'package:twin_ar/core/models/auth/auth_result.dart';
import 'package:twin_ar/core/models/auth/user_role.dart';
import 'package:twin_ar/features/virtual_try_on/services/mock_virtual_try_on_photo_picker_service.dart';
import 'package:twin_ar/features/virtual_try_on/services/mock_virtual_try_on_service.dart';
import 'package:twin_ar/features/virtual_try_on/services/virtual_try_on_exception.dart';
import 'package:twin_ar/features/virtual_try_on/viewmodels/virtual_try_on_session_viewmodel.dart';
import 'package:twin_ar/features/virtual_try_on/views/virtual_try_on_session_view.dart';

import '../virtual_try_on_test_helpers.dart';

Uint8List _validPhotoBytes() {
  final image = img.Image(width: 900, height: 1400);
  img.fill(image, color: img.ColorRgb8(100, 120, 140));
  return Uint8List.fromList(img.encodePng(image));
}

Uint8List _validResultBytes() {
  final image = img.Image(width: 400, height: 600);
  img.fill(image, color: img.ColorRgb8(200, 60, 90));
  return Uint8List.fromList(img.encodePng(image));
}

AuthSessionState _signedInAuth() {
  final auth = AuthSessionState();
  auth.setSession(
    AuthResult.success(
      userId: 'test-uid',
      email: 'a@b.com',
      role: UserRole.customer,
    ),
  );
  return auth;
}

void main() {
  Widget harness(VirtualTryOnSessionViewModel vm) {
    return MaterialApp(
      routes: {
        RouteNames.login: (context) => const Scaffold(body: Text('Login')),
      },
      home: ChangeNotifierProvider.value(
        value: vm,
        child: const VirtualTryOnSessionView(),
      ),
    );
  }

  VirtualTryOnSessionViewModel buildVm({
    MockVirtualTryOnService? service,
    MockVirtualTryOnPhotoPickerService? picker,
  }) {
    return VirtualTryOnSessionViewModel(
      repository: FakeVtoProductDetailsRepository(
        product: buildEligibleVtoProduct(),
        productId: kEligibleVtoProductId,
      ),
      service: service ?? MockVirtualTryOnService(),
      photoPicker: picker ?? MockVirtualTryOnPhotoPickerService(),
      shoppingState: CustomerShoppingState(
        MockFavoritesRepository(),
        MockCartRepository(),
      ),
      authSessionState: _signedInAuth(),
      productId: kEligibleVtoProductId,
      colorKey: 'blue',
      size: 'm',
      idempotencyKey: 'vto_test_key',
    );
  }

  testWidgets('shows the capture prompt with no front-camera affordance', (
    tester,
  ) async {
    await tester.pumpWidget(harness(buildVm()));
    await tester.pumpAndSettle();

    expect(find.text('Take Photo'), findsOneWidget);
    expect(find.text('Choose from Gallery'), findsOneWidget);
    expect(find.textContaining('Front Camera'), findsNothing);
    expect(find.textContaining('front camera'), findsNothing);
  });

  testWidgets('picking from gallery moves to the photo preview', (
    tester,
  ) async {
    final picker = MockVirtualTryOnPhotoPickerService()
      ..nextGalleryResult = _validPhotoBytes();
    await tester.pumpWidget(harness(buildVm(picker: picker)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose from Gallery'));
    await tester.pumpAndSettle();

    expect(find.text('Use This Photo'), findsOneWidget);
    expect(find.textContaining('Retake'), findsOneWidget);
  });

  testWidgets(
    'the full happy path reaches a result with cart/retake/delete actions',
    (tester) async {
      final service = MockVirtualTryOnService()
        ..downloadBytes = _validResultBytes();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextGalleryResult = _validPhotoBytes();
      await tester.pumpWidget(
        harness(buildVm(service: service, picker: picker)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use This Photo'));
      await tester.pumpAndSettle();

      expect(find.text('Add to Cart'), findsOneWidget);
      expect(find.text('Retake Photo'), findsOneWidget);
      expect(find.text('Delete This Preview'), findsOneWidget);
      expect(find.textContaining('visual estimate'), findsOneWidget);
      expect(service.generateCalls, ['vto_test_key']);
    },
  );

  testWidgets(
    'the selected colour chip is clearly readable (solid background, white '
    'label + checkmark) while the unselected chip is unchanged',
    (tester) async {
      final service = MockVirtualTryOnService()
        ..downloadBytes = _validResultBytes();
      final picker = MockVirtualTryOnPhotoPickerService()
        ..nextGalleryResult = _validPhotoBytes();
      // Default variant is 'blue' -> "Sky Blue" is selected, "Black" is not.
      await tester.pumpWidget(
        harness(buildVm(service: service, picker: picker)),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Choose from Gallery'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Use This Photo'));
      await tester.pumpAndSettle();

      final chips = tester
          .widgetList<ChoiceChip>(find.byType(ChoiceChip))
          .toList();
      expect(chips.length, 2);

      final selectedChip = chips.firstWhere((c) => c.selected);
      final unselectedChip = chips.firstWhere((c) => !c.selected);

      // Selected ("Sky Blue"): solid green background matching Add to
      // Cart, white label, white checkmark - never the faint 15%-alpha tint.
      expect(selectedChip.selectedColor, AppColors.primary);
      expect(selectedChip.checkmarkColor, AppColors.white);
      expect(selectedChip.labelStyle?.color, AppColors.white);

      final addToCartButton = tester.widget<ElevatedButton>(
        find.widgetWithText(ElevatedButton, 'Add to Cart'),
      );
      final addToCartStyle = addToCartButton.style!.backgroundColor!.resolve(
        {},
      );
      expect(selectedChip.selectedColor, addToCartStyle);

      // Unselected ("Black"): no custom label style - falls back to the
      // ambient chip theme default, same as before this fix. (`selectedColor`
      // / `checkmarkColor` are declared once per chip for whenever it BECOMES
      // selected - Flutter only actually paints them while `selected` is
      // true, so they are intentionally identical across both chips here.)
      expect(unselectedChip.labelStyle, isNull);

      // The two chips remain visually distinct: one is flagged `selected`
      // with a white label forced on, the other renders with the chip
      // theme's own default (unstyled) label.
      expect(selectedChip.selected, isTrue);
      expect(unselectedChip.selected, isFalse);
      expect(
        selectedChip.labelStyle?.color,
        isNot(equals(unselectedChip.labelStyle?.color)),
      );
    },
  );

  testWidgets('a failure shows the mapped message with a Retry action', (
    tester,
  ) async {
    final service = MockVirtualTryOnService()
      ..nextGenerateError = const VirtualTryOnException(
        VirtualTryOnErrorKind.rateLimited,
        "You've reached the try-on limit for now. Please try again later.",
      );
    final picker = MockVirtualTryOnPhotoPickerService()
      ..nextGalleryResult = _validPhotoBytes();
    await tester.pumpWidget(harness(buildVm(service: service, picker: picker)));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Choose from Gallery'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use This Photo'));
    await tester.pumpAndSettle();

    expect(find.text('Retry'), findsOneWidget);
    expect(find.textContaining('reached the try-on limit'), findsOneWidget);
  });

  testWidgets('back navigation while generating asks for confirmation', (
    tester,
  ) async {
    final generateGate = Completer<void>();
    final service = MockVirtualTryOnService()
      ..generateGate = generateGate
      ..downloadBytes = _validResultBytes();
    final picker = MockVirtualTryOnPhotoPickerService()
      ..nextGalleryResult = _validPhotoBytes();
    await tester.pumpWidget(harness(buildVm(service: service, picker: picker)));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Choose from Gallery'));
    await tester.pumpAndSettle();

    // The generate call is now held open by generateGate — the screen is
    // reliably parked on "generating". `pumpAndSettle` can't be used here:
    // the indeterminate CircularProgressIndicator animates forever and would
    // never let it settle.
    await tester.tap(find.text('Use This Photo'));
    await tester.pump(); // uploading
    await tester.pump(); // generating
    expect(find.text('Generating your preview'), findsOneWidget);

    // Simulate the Android system back button (mirrors the established
    // pattern in admin_product_form_test.dart's PopScope test).
    final dynamic navigatorState = tester.state(find.byType(Navigator));
    navigatorState.maybePop();
    await tester.pump();

    expect(find.text('Leave while generating?'), findsOneWidget);

    // Dismiss the dialog, then release the gate so no Future is left pending
    // at the end of the test.
    await tester.tap(find.text('Stay'));
    await tester.pump();
    generateGate.complete();
    await tester.pump();
    await tester.pump();
  });
}
