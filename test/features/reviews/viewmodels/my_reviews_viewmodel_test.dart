import 'package:flutter_test/flutter_test.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/features/product_details/models/product_detail_model.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';
import 'package:twin_ar/features/reviews/viewmodels/my_reviews_viewmodel.dart';

Future<void> _flush() => Future.delayed(Duration.zero);

ProductDetailModel _product(String id, String title) {
  return ProductDetailModel(
    summary: ProductSummaryModel(
      id: id,
      title: title,
      imageAssetPath: 'assets/images/placeholder.png',
      currentPrice: 'Rs 1,000/-',
    ),
    stockQuantity: 5,
    categoryId: 'furniture',
    categoryKind: ProductCategory.furniture,
    experienceType: ProductExperienceType.none,
    subcategory: 'Chairs',
    gallery: const [],
    description: 'A test product.',
    availableColors: const [],
    availableSizes: const [],
    specifications: const [],
    deliveryEstimate: '3-5 Business Days',
  );
}

/// Minimal, fully-controllable [ProductDetailsRepository] serving a fixed
/// map of products - throws for any id not in [products], and can be made
/// to always throw via [alwaysFail] (simulating a resolution failure for
/// every product, e.g. a genuinely deleted one).
class _FakeProductDetailsRepository implements ProductDetailsRepository {
  final Map<String, ProductDetailModel> products;
  bool alwaysFail;
  final List<String> calls = [];

  _FakeProductDetailsRepository(this.products, {this.alwaysFail = false});

  @override
  Future<ProductDetailModel> getProductDetails(String productId) async {
    calls.add(productId);
    if (alwaysFail || !products.containsKey(productId)) {
      throw StateError('Product not found for ID: $productId');
    }
    return products[productId]!;
  }
}

void main() {
  group('MyReviewsViewModel — loading / listing', () {
    test('starts loading, then resolves to the honest empty state for a '
        'customer with no reviews', () async {
      final reviews = MockReviewsRepository(currentUserId: 'u1');
      final products = _FakeProductDetailsRepository({});
      final viewModel = MyReviewsViewModel(
        repository: reviews,
        productDetailsRepository: products,
      );

      expect(viewModel.isLoading, true);
      await _flush();

      expect(viewModel.isLoading, false);
      expect(viewModel.hasLoadError, false);
      expect(viewModel.isEmpty, true);
      expect(viewModel.reviews, isEmpty);
    });

    test('lists every review the customer wrote, newest first, and '
        'resolves each product\'s summary', () async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1')
        ..markEligible('u1', 'p2');
      await reviews.submitReview(
        productId: 'p1',
        rating: 3,
        body: 'The first review, written a little earlier than the next.',
      );
      reviews.now = () => DateTime.now().add(const Duration(minutes: 1));
      await reviews.submitReview(
        productId: 'p2',
        rating: 5,
        body: 'The second review, written a little later than the first.',
      );

      final products = _FakeProductDetailsRepository({
        'p1': _product('p1', 'Luna Accent Chair'),
        'p2': _product('p2', 'Oak Side Table'),
      });
      final viewModel = MyReviewsViewModel(
        repository: reviews,
        productDetailsRepository: products,
      );
      await _flush();
      await _flush(); // let the background product-summary resolution land

      expect(viewModel.reviews.length, 2);
      expect(viewModel.reviews.first.productId, 'p2'); // newest first
      expect(viewModel.productSummaryFor('p1')!.title, 'Luna Accent Chair');
      expect(viewModel.productSummaryFor('p2')!.title, 'Oak Side Table');
    });

    test('a product resolution failure never hides the review itself - it '
        'just has no summary', () async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A review whose product will fail to resolve in this test.',
      );

      final products = _FakeProductDetailsRepository({}, alwaysFail: true);
      final viewModel = MyReviewsViewModel(
        repository: reviews,
        productDetailsRepository: products,
      );
      await _flush();
      await _flush();

      expect(viewModel.reviews, hasLength(1));
      expect(viewModel.productSummaryFor('p1'), isNull);
    });

    test(
      'resolves each distinct product exactly once, never re-fetched '
      'for a second review of the same product... across a refresh',
      () async {
        final reviews = MockReviewsRepository(currentUserId: 'u1')
          ..markEligible('u1', 'p1');
        await reviews.submitReview(
          productId: 'p1',
          rating: 4,
          body: 'A review whose product summary should be cached here.',
        );
        final products = _FakeProductDetailsRepository({
          'p1': _product('p1', 'Luna Accent Chair'),
        });
        final viewModel = MyReviewsViewModel(
          repository: reviews,
          productDetailsRepository: products,
        );
        await _flush();
        await _flush();
        expect(products.calls, ['p1']);

        await viewModel.refresh();
        await _flush();
        await _flush();

        expect(products.calls, ['p1']); // not re-fetched
      },
    );
  });

  group('MyReviewsViewModel — delete', () {
    test('deleting a review removes it from the list immediately', () async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A review that will be deleted during this test case.',
      );
      final viewModel = MyReviewsViewModel(
        repository: reviews,
        productDetailsRepository: _FakeProductDetailsRepository({}),
      );
      await _flush();
      expect(viewModel.reviews, hasLength(1));

      final review = viewModel.reviews.single;
      final error = await viewModel.deleteReview(review);

      expect(error, isNull);
      expect(viewModel.reviews, isEmpty);
      expect(await reviews.myReviewFor('p1'), isNull);
    });

    test(
      'a second overlapping delete for the SAME review is refused',
      () async {
        final reviews = MockReviewsRepository(currentUserId: 'u1')
          ..markEligible('u1', 'p1');
        await reviews.submitReview(
          productId: 'p1',
          rating: 4,
          body: 'A review deleted concurrently twice in this test case.',
        );
        final viewModel = MyReviewsViewModel(
          repository: reviews,
          productDetailsRepository: _FakeProductDetailsRepository({}),
        );
        await _flush();
        final review = viewModel.reviews.single;

        final firstDelete = viewModel.deleteReview(review);
        final secondDelete = viewModel.deleteReview(review);

        expect(
          await secondDelete,
          'Please wait for the current request to finish.',
        );
        expect(await firstDelete, isNull);
      },
    );
  });
}
