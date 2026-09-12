import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_color_option.dart';
import 'package:twin_ar/core/models/product/product_size.dart';
import 'package:twin_ar/features/virtual_try_on/viewmodels/virtual_try_on_setup_viewmodel.dart';

import '../virtual_try_on_test_helpers.dart';

void main() {
  test('loads an eligible product and defaults colour/size', () async {
    final product = buildEligibleVtoProduct();
    final viewModel = VirtualTryOnSetupViewModel(
      repository: FakeVtoProductDetailsRepository(
        product: product,
        productId: kEligibleVtoProductId,
      ),
      productId: kEligibleVtoProductId,
    );

    expect(viewModel.isLoading, true);
    await Future.delayed(Duration.zero);

    expect(viewModel.isLoading, false);
    expect(viewModel.error, isNull);
    expect(viewModel.product, isNotNull);
    expect(viewModel.selectedColor, ProductColorOption.blue);
    expect(viewModel.selectedSize, ProductSize.m);
  });

  test('shows an error for a non-eligible product', () async {
    final product = buildNonVtoProduct();
    final viewModel = VirtualTryOnSetupViewModel(
      repository: FakeVtoProductDetailsRepository(
        product: product,
        productId: 'non-vto-product',
      ),
      productId: 'non-vto-product',
    );

    await Future.delayed(Duration.zero);

    expect(viewModel.isLoading, false);
    expect(viewModel.error, "Virtual Try-On isn't available for this product.");
    expect(viewModel.canStart, false);
  });

  test('shows an error when a repository load fails', () async {
    final viewModel = VirtualTryOnSetupViewModel(
      repository: FakeVtoProductDetailsRepository(
        product: buildEligibleVtoProduct(),
        productId: kEligibleVtoProductId,
        errorToThrow: Exception('boom'),
      ),
      productId: kEligibleVtoProductId,
    );

    await Future.delayed(Duration.zero);

    expect(viewModel.isLoading, false);
    expect(
      viewModel.error,
      'Failed to load product details for Virtual Try-On.',
    );
  });

  test(
    'carries over the customer\'s already-selected eligible colour/size',
    () async {
      final product = buildEligibleVtoProduct();
      final viewModel = VirtualTryOnSetupViewModel(
        repository: FakeVtoProductDetailsRepository(
          product: product,
          productId: kEligibleVtoProductId,
        ),
        productId: kEligibleVtoProductId,
        initialColorKey: ProductColorOption.black.name,
        initialSize: ProductSize.l.name,
      );

      await Future.delayed(Duration.zero);

      expect(viewModel.selectedColor, ProductColorOption.black);
      expect(viewModel.selectedSize, ProductSize.l);
    },
  );

  test('Stage 6: a colour missing its own preview asset does NOT block the '
      'whole product — the product stays eligible (at least one colour '
      'resolves) and the setup screen simply loads with a different colour '
      'selected', () async {
    final product = buildEligibleVtoProduct(
      missingAssetForColors: {ProductColorOption.black},
    );
    final viewModel = VirtualTryOnSetupViewModel(
      repository: FakeVtoProductDetailsRepository(
        product: product,
        productId: kEligibleVtoProductId,
      ),
      productId: kEligibleVtoProductId,
    );

    await Future.delayed(Duration.zero);

    expect(viewModel.error, isNull);
    // Blue still resolves, so it's the one selected by default.
    expect(viewModel.selectedColor, ProductColorOption.blue);
    expect(viewModel.colorHasPreview(product, ProductColorOption.blue), isTrue);
    // Black has no asset — shown as a valid colour, but no preview.
    expect(
      viewModel.colorHasPreview(product, ProductColorOption.black),
      isFalse,
    );
  });

  test(
    'a product where NO colour has any asset at all is genuinely ineligible',
    () async {
      final product = buildEligibleVtoProduct(
        // default colours are blue + black — remove the asset for both.
        missingAssetForColors: const {
          ProductColorOption.blue,
          ProductColorOption.black,
        },
      );
      final viewModel = VirtualTryOnSetupViewModel(
        repository: FakeVtoProductDetailsRepository(
          product: product,
          productId: kEligibleVtoProductId,
        ),
        productId: kEligibleVtoProductId,
      );

      await Future.delayed(Duration.zero);

      expect(
        viewModel.error,
        "Virtual Try-On isn't available for this product.",
      );
      expect(viewModel.selectedColor, isNull);
    },
  );

  test(
    'selectColor / colorHasPreview never select a colour with no resolvable asset (defence in depth)',
    () async {
      final product = buildEligibleVtoProduct();
      final viewModel = VirtualTryOnSetupViewModel(
        repository: FakeVtoProductDetailsRepository(
          product: product,
          productId: kEligibleVtoProductId,
        ),
        productId: kEligibleVtoProductId,
      );
      await Future.delayed(Duration.zero);

      expect(viewModel.selectedColor, ProductColorOption.blue);
      // Pink isn't one of this product's own colours/assets at all.
      expect(
        viewModel.colorHasPreview(product, ProductColorOption.pink),
        false,
      );
      viewModel.selectColor(ProductColorOption.pink);
      expect(viewModel.selectedColor, ProductColorOption.blue);
    },
  );

  test('canStart requires eligibility, a valid colour, and consent', () async {
    final product = buildEligibleVtoProduct();
    final viewModel = VirtualTryOnSetupViewModel(
      repository: FakeVtoProductDetailsRepository(
        product: product,
        productId: kEligibleVtoProductId,
      ),
      productId: kEligibleVtoProductId,
    );
    await Future.delayed(Duration.zero);

    expect(viewModel.canStart, false);
    viewModel.setConsentChecked(true);
    expect(viewModel.canStart, true);
    viewModel.setConsentChecked(false);
    expect(viewModel.canStart, false);
  });

  test('startNewAttemptIdempotencyKey mints unique keys', () async {
    final product = buildEligibleVtoProduct();
    final viewModel = VirtualTryOnSetupViewModel(
      repository: FakeVtoProductDetailsRepository(
        product: product,
        productId: kEligibleVtoProductId,
      ),
      productId: kEligibleVtoProductId,
    );
    await Future.delayed(Duration.zero);

    final a = viewModel.startNewAttemptIdempotencyKey();
    final b = viewModel.startNewAttemptIdempotencyKey();
    expect(a, isNot(equals(b)));
    expect(a.startsWith('vto_'), true);
  });
}
