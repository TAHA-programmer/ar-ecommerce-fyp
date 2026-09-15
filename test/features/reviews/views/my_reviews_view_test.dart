import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/routes/route_names.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/features/product_details/models/product_detail_model.dart';
import 'package:twin_ar/features/product_details/repositories/product_details_repository.dart';
import 'package:twin_ar/features/reviews/models/write_review_args.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';
import 'package:twin_ar/features/reviews/viewmodels/my_reviews_viewmodel.dart';
import 'package:twin_ar/features/reviews/views/my_reviews_view.dart';

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

class _FakeProductDetailsRepository implements ProductDetailsRepository {
  final Map<String, ProductDetailModel> products;
  _FakeProductDetailsRepository(this.products);

  @override
  Future<ProductDetailModel> getProductDetails(String productId) async {
    final product = products[productId];
    if (product == null) {
      throw StateError('Product not found for ID: $productId');
    }
    return product;
  }
}

Widget _createWidget(
  MockReviewsRepository reviews, {
  Map<String, ProductDetailModel> products = const {},
}) {
  return MaterialApp(
    home: ChangeNotifierProvider<MyReviewsViewModel>(
      create: (_) => MyReviewsViewModel(
        repository: reviews,
        productDetailsRepository: _FakeProductDetailsRepository(products),
      ),
      child: const MyReviewsView(),
    ),
    // A minimal stand-in for the real Write/Edit Review screen - just
    // enough to prove `_edit` actually navigated (and with the right
    // arguments) once the confirmation dialog is accepted.
    onGenerateRoute: (settings) {
      if (settings.name == RouteNames.writeReview) {
        final args = settings.arguments as WriteReviewArgs;
        return MaterialPageRoute(
          builder: (context) => Scaffold(
            body: Center(child: Text('Editing ${args.productTitle}')),
          ),
        );
      }
      return null;
    },
  );
}

void main() {
  group('MyReviewsView', () {
    testWidgets('shows the honest empty state for a customer with no '
        'reviews', (tester) async {
      final reviews = MockReviewsRepository(currentUserId: 'u1');
      await tester.pumpWidget(_createWidget(reviews));
      await tester.pumpAndSettle();

      expect(find.text("You haven't written any reviews yet"), findsOneWidget);
    });

    testWidgets('lists every review with its resolved product title', (
      tester,
    ) async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A perfectly good review body for this test case here.',
      );

      await tester.pumpWidget(
        _createWidget(
          reviews,
          products: {'p1': _product('p1', 'Luna Accent Chair')},
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Luna Accent Chair'), findsOneWidget);
      expect(
        find.text('A perfectly good review body for this test case here.'),
        findsOneWidget,
      );
    });

    testWidgets('deleting a review, after confirming, removes it from the '
        'list', (tester) async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A review that will be deleted during this test case.',
      );

      await tester.pumpWidget(
        _createWidget(
          reviews,
          products: {'p1': _product('p1', 'Luna Accent Chair')},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();

      expect(find.text('Delete Review?'), findsOneWidget);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Delete'));
      await tester.pump(); // let the async delete + toast fire
      await tester.pump();

      expect(find.text('Luna Accent Chair'), findsNothing);
      expect(find.text("You haven't written any reviews yet"), findsOneWidget);
      // Drain the toast's auto-dismiss timer before the test tears down.
      await tester.pump(const Duration(seconds: 4));
    });

    testWidgets('cancelling the delete confirmation keeps the review', (
      tester,
    ) async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A review that should survive a cancelled delete here.',
      );

      await tester.pumpWidget(
        _createWidget(
          reviews,
          products: {'p1': _product('p1', 'Luna Accent Chair')},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Delete'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Luna Accent Chair'), findsOneWidget);
      expect(await reviews.myReviewFor('p1'), isNotNull);
    });

    testWidgets('tapping Edit shows a confirmation dialog before navigating '
        'anywhere', (tester) async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A review whose edit action is confirmed in this test.',
      );

      await tester.pumpWidget(
        _createWidget(
          reviews,
          products: {'p1': _product('p1', 'Luna Accent Chair')},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Review?'), findsOneWidget);
      // Still on My Reviews - confirming hasn't happened yet.
      expect(find.text('Editing Luna Accent Chair'), findsNothing);
    });

    testWidgets('cancelling the edit confirmation never navigates', (
      tester,
    ) async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A review whose edit is cancelled before it starts here.',
      );

      await tester.pumpWidget(
        _createWidget(
          reviews,
          products: {'p1': _product('p1', 'Luna Accent Chair')},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Edit Review?'), findsNothing);
      expect(find.text('Editing Luna Accent Chair'), findsNothing);
      expect(find.text('Luna Accent Chair'), findsOneWidget); // still here
    });

    testWidgets('confirming the edit dialog navigates to the write/edit '
        'screen with the right arguments', (tester) async {
      final reviews = MockReviewsRepository(currentUserId: 'u1')
        ..markEligible('u1', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 4,
        body: 'A review whose edit is confirmed and followed through here.',
      );

      await tester.pumpWidget(
        _createWidget(
          reviews,
          products: {'p1': _product('p1', 'Luna Accent Chair')},
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Edit'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Edit'));
      await tester.pumpAndSettle();

      expect(find.text('Editing Luna Accent Chair'), findsOneWidget);
    });
  });
}
