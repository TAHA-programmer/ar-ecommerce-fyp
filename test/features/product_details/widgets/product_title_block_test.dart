import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:twin_ar/app/viewmodels/auth_session_state.dart';
import 'package:twin_ar/core/models/product/product_category.dart';
import 'package:twin_ar/core/models/product/product_experience_type.dart';
import 'package:twin_ar/core/models/product/product_summary_model.dart';
import 'package:twin_ar/features/product_details/models/product_detail_model.dart';
import 'package:twin_ar/features/product_details/widgets/product_title_block.dart';
import 'package:twin_ar/features/reviews/repositories/mock_reviews_repository.dart';
import 'package:twin_ar/features/reviews/viewmodels/reviews_viewmodel.dart';

ProductDetailModel _detail({
  ProductCategory category = ProductCategory.clothing,
  double staticRating = 4.8,
  int staticReviewCount = 23,
}) {
  return ProductDetailModel(
    summary: ProductSummaryModel(
      id: 'p1',
      title: 'Classic Oxford Shirt',
      imageAssetPath: 'assets/images/placeholder.png',
      currentPrice: 'Rs 3,500/-',
      // The STATIC seed rating/reviewCount - Stage 12 must NEVER show these
      // on the title block any more, only the live productStats aggregate.
      rating: staticRating,
      reviewCount: staticReviewCount,
    ),
    stockQuantity: 5,
    categoryId: category.name,
    categoryKind: category,
    experienceType: ProductExperienceType.none,
    subcategory: 'Shirts',
    gallery: const [],
    description: 'A test product.',
    availableColors: const [],
    availableSizes: const [],
    specifications: const [],
    deliveryEstimate: '3-5 Business Days',
  );
}

Widget _createWidget(
  ProductDetailModel product,
  MockReviewsRepository reviews,
) {
  return MaterialApp(
    home: Scaffold(
      body: ChangeNotifierProvider<ReviewsViewModel>(
        create: (_) => ReviewsViewModel(
          repository: reviews,
          authSessionState: AuthSessionState(),
          productId: product.summary.id,
        ),
        child: ProductTitleBlock(product: product),
      ),
    ),
  );
}

void main() {
  group('ProductTitleBlock rating (Ratings/Reviews v1 Stage 12)', () {
    testWidgets(
      'a clothing product with published reviews shows the LIVE average/'
      'count, never the static seed rating/reviewCount',
      (tester) async {
        final reviews = MockReviewsRepository(currentUserId: 'buyer')
          ..markEligible('buyer', 'p1');
        await reviews.submitReview(
          productId: 'p1',
          rating: 5,
          body: 'A genuinely great shirt, fits perfectly and looks sharp.',
        );

        await tester.pumpWidget(_createWidget(_detail(), reviews));
        await tester.pumpAndSettle();

        expect(find.text('5.0'), findsOneWidget);
        expect(find.text('(1)'), findsOneWidget);
        // The static seed values must never appear.
        expect(find.text('4.8'), findsNothing);
        expect(find.text('(23)'), findsNothing);
      },
    );

    testWidgets('a clothing product with NO published reviews shows the honest '
        '"No reviews yet" empty state, never a fabricated "0.0 ★ (0)"', (
      tester,
    ) async {
      final reviews = MockReviewsRepository(); // nothing submitted

      await tester.pumpWidget(_createWidget(_detail(), reviews));
      await tester.pumpAndSettle();

      expect(find.text('No reviews yet'), findsOneWidget);
      expect(find.text('0.0'), findsNothing);
      expect(find.text('(0)'), findsNothing);
      // The static seed values must never appear either.
      expect(find.text('4.8'), findsNothing);
    });

    testWidgets('a non-clothing product never shows the rating row at all - '
        'unchanged pre-existing gate', (tester) async {
      final reviews = MockReviewsRepository(currentUserId: 'buyer')
        ..markEligible('buyer', 'p1');
      await reviews.submitReview(
        productId: 'p1',
        rating: 5,
        body: 'A review that must not surface on a furniture title block.',
      );

      await tester.pumpWidget(
        _createWidget(_detail(category: ProductCategory.furniture), reviews),
      );
      await tester.pumpAndSettle();

      expect(find.text('5.0'), findsNothing);
      expect(find.text('No reviews yet'), findsNothing);
    });
  });
}
